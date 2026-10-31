const crypto = require('node:crypto');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { defineSecret } = require('firebase-functions/params');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

if (getApps().length === 0) initializeApp();

const cloudinaryApiKey = defineSecret('CLOUDINARY_API_KEY');
const cloudinaryApiSecret = defineSecret('CLOUDINARY_API_SECRET');
const cloudinaryCloudName = 'oyfgbne4';
const db = getFirestore();

function cloudinaryAsset(url) {
  try {
    const parsed = new URL(url);
    if (parsed.hostname !== 'res.cloudinary.com') return null;
    const parts = parsed.pathname.split('/').filter(Boolean);
    if (parts[0] !== cloudinaryCloudName) return null;
    const typeIndex = parts.findIndex((part) => ['image', 'video', 'raw'].includes(part));
    const uploadIndex = parts.indexOf('upload', typeIndex + 1);
    if (typeIndex < 0 || uploadIndex < 0) return null;
    let assetParts = parts.slice(uploadIndex + 1);
    const versionIndex = assetParts.findIndex((part) => /^v\d+$/.test(part));
    if (versionIndex >= 0) assetParts = assetParts.slice(versionIndex + 1);
    else if (/^(c_|f_|q_|w_|h_|so_|eo_|ac_|br_|vc_|du_|fl_)/.test(assetParts[0] || '')) return null;
    if (assetParts.length === 0) return null;
    assetParts[assetParts.length - 1] = assetParts.at(-1).replace(/\.[^.]+$/, '');
    const publicId = assetParts.join('/');
    if (!publicId) return null;
    return { publicId, resourceType: parts[typeIndex] };
  } catch (_) {
    return null;
  }
}

async function deleteCloudinaryAsset(asset) {
  const apiKey = cloudinaryApiKey.value();
  const apiSecret = cloudinaryApiSecret.value();
  if (!apiKey || !apiSecret) {
    throw new HttpsError('failed-precondition', 'ตั้งค่า Cloudinary API key และ API secret ใน Firebase Secrets ก่อนลบบัญชี');
  }
  const timestamp = Math.floor(Date.now() / 1000);
  const signature = crypto.createHash('sha1')
    .update(`public_id=${asset.publicId}&timestamp=${timestamp}${apiSecret}`)
    .digest('hex');
  const body = new URLSearchParams({
    public_id: asset.publicId,
    timestamp: String(timestamp),
    api_key: apiKey,
    signature,
  });
  const response = await fetch(
    `https://api.cloudinary.com/v1_1/${cloudinaryCloudName}/${asset.resourceType}/destroy`,
    { method: 'POST', body },
  );
  if (!response.ok) throw new Error(`Cloudinary delete failed (${response.status})`);
  const result = await response.json();
  if (result.result !== 'ok' && result.result !== 'not found') {
    throw new Error(`Cloudinary rejected asset deletion: ${result.result}`);
  }
}

function addAsset(url, assets) {
  const asset = typeof url === 'string' ? cloudinaryAsset(url) : null;
  if (asset) assets.set(`${asset.resourceType}:${asset.publicId}`, asset);
}

async function deleteTree(ref) {
  await db.recursiveDelete(ref);
}

async function deleteQuery(query) {
  while (true) {
    const page = await query.limit(400).get();
    if (page.empty) break;
    const writer = db.bulkWriter();
    for (const doc of page.docs) writer.delete(doc.ref);
    await writer.close();
    if (page.size < 400) break;
  }
}

async function collectAccountAssets(uid, profile) {
  const assets = new Map();
  addAsset(profile.photoUrl, assets);
  addAsset(profile.coverUrl, assets);

  const [posts, stories, communityPosts, pages, chats, communities] = await Promise.all([
    db.collection('posts').where('authorId', '==', uid).get(),
    db.collection('stories').where('authorId', '==', uid).get(),
    db.collectionGroup('posts').where('authorId', '==', uid).get(),
    db.collection('pages').where('ownerId', '==', uid).get(),
    db.collection('chats').where('participants', 'array-contains', uid).get(),
    db.collection('communities').where('ownerId', '==', uid).get(),
  ]);
  for (const snap of [posts, stories, communityPosts, pages]) {
    for (const doc of snap.docs) {
      for (const field of ['mediaUrl', 'sharedMediaUrl', 'photoUrl', 'coverUrl']) addAsset(doc.data()[field], assets);
    }
  }
  for (const page of pages.docs) {
    const pagePosts = await db.collection('posts').where('pageId', '==', page.id).get();
    for (const post of pagePosts.docs) addAsset(post.data().mediaUrl, assets);
  }
  for (const community of communities.docs) {
    const communityPosts = await community.ref.collection('posts').get();
    for (const post of communityPosts.docs) addAsset(post.data().mediaUrl, assets);
  }
  for (const chat of chats.docs) {
    const messages = await chat.ref.collection('messages').where('senderId', '==', uid).get();
    for (const message of messages.docs) addAsset(message.data().imageUrl, assets);
  }
  return assets;
}

async function removeAccountReferences(uid) {
  const users = db.collection('users');
  let cursor;
  while (true) {
    let query = users.orderBy('__name__').limit(250);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    const writer = db.bulkWriter();
    for (const user of page.docs) {
      if (user.id === uid) continue;
      const data = user.data();
      const update = {};
      if ((data.followers || []).includes(uid)) update.followers = FieldValue.arrayRemove(uid);
      if ((data.following || []).includes(uid)) update.following = FieldValue.arrayRemove(uid);
      if (Object.keys(update).length) {
        writer.update(user.ref, update);
      }
      for (const collection of ['friends', 'friendRequests', 'followRequests', 'blocks', 'hiddenPosts', 'mutedAuthors']) {
        writer.delete(user.ref.collection(collection).doc(uid));
      }
    }
    await writer.close();
    cursor = page.docs.at(-1);
    if (page.size < 250) break;
  }
}

async function deleteMyAccountData(uid) {
  const userRef = db.collection('users').doc(uid);
  const userSnap = await userRef.get();
  const profile = userSnap.data() || {};
  const assets = await collectAccountAssets(uid, profile);

  // Delete remote media before removing its Firestore URLs so failures can be retried.
  for (const asset of assets.values()) await deleteCloudinaryAsset(asset);

  await removeAccountReferences(uid);

  await deleteQuery(db.collectionGroup('comments').where('authorId', '==', uid));
  await deleteQuery(db.collectionGroup('responses').where('uid', '==', uid));
  await deleteQuery(db.collectionGroup('notifications').where('fromUid', '==', uid));
  await deleteQuery(db.collection('reports').where('reporterId', '==', uid));
  await deleteQuery(db.collection('posts').where('authorId', '==', uid));
  await deleteQuery(db.collection('stories').where('authorId', '==', uid));
  await deleteQuery(db.collection('events').where('hostId', '==', uid));

  const communityPosts = await db.collectionGroup('posts').where('authorId', '==', uid).get();
  for (const post of communityPosts.docs) {
    if (post.ref.path.startsWith('communities/')) await deleteTree(post.ref);
  }

  const sharedPosts = await db.collection('posts').where('sharedAuthorId', '==', uid).get();
  for (const post of sharedPosts.docs) await deleteTree(post.ref);

  const pages = await db.collection('pages').get();
  for (const page of pages.docs) {
    if (page.data().ownerId === uid) await deleteTree(page.ref);
    else {
      const data = page.data();
      const patch = {};
      if ((data.memberIds || []).includes(uid)) patch.memberIds = FieldValue.arrayRemove(uid);
      if ((data.pendingRequests || []).includes(uid)) patch.pendingRequests = FieldValue.arrayRemove(uid);
      if (Object.keys(patch).length) await page.ref.update(patch);
    }
  }

  const communities = await db.collection('communities').get();
  for (const community of communities.docs) {
    if (community.data().ownerId === uid) {
      await deleteTree(community.ref);
      continue;
    }
    const refs = ['members', 'joinRequests', 'banned'].map((name) => community.ref.collection(name).doc(uid));
    await Promise.all(refs.map((ref) => ref.delete()));
    await deleteQuery(community.ref.collection('reports').where('reporterId', '==', uid));
  }

  const chats = await db.collection('chats').where('participants', 'array-contains', uid).get();
  for (const chat of chats.docs) {
    const data = chat.data();
    const participants = (data.participants || []).filter((id) => id !== uid);
    if (data.type !== 'group' || participants.length === 0) {
      await deleteTree(chat.ref);
      continue;
    }
    await deleteQuery(chat.ref.collection('messages').where('senderId', '==', uid));
    const patch = { participants, lastMessage: '' };
    if (data.ownerId === uid) patch.ownerId = participants[0];
    await chat.ref.update(patch);
  }

  const events = await db.collection('events').get();
  for (const event of events.docs) {
    if (event.data().hostId === uid) continue;
    await event.ref.collection('responses').doc(uid).delete();
  }

  await deleteTree(userRef);
  await getAuth().deleteUser(uid);
}

exports.deleteMyAccount = onCall(
  { timeoutSeconds: 540, memory: '1GiB', secrets: [cloudinaryApiKey, cloudinaryApiSecret] },
  async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบก่อน');
    const authTime = Number(request.auth.token.auth_time || 0);
    if (Date.now() / 1000 - authTime > 5 * 60) {
      throw new HttpsError('failed-precondition', 'เซสชันหมดอายุ กรุณายืนยันรหัสผ่านอีกครั้งแล้วลองใหม่');
    }
    await deleteMyAccountData(request.auth.uid);
    return { deleted: true };
  },
);
