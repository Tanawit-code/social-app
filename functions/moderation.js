// ระบบดูแลโพสต์: รายงาน -> แจ้งแอดมิน -> ซ่อนอัตโนมัติ/ซ่อนโดยแอดมิน -> ตรวจว่าแก้ไขจริง -> แสดงอีกครั้ง
//
// สถานะซ่อนเก็บบนเอกสารโพสต์ (แก้ได้เฉพาะ server — rules ไม่ให้ client เขียนฟิลด์เหล่านี้):
//   hidden: bool, hiddenBy: 'reports' | 'admin', hiddenReason, hiddenAt,
//   hiddenUntil: Timestamp | null (null = ซ่อนจนกว่าเจ้าของจะแก้ไข),
//   hiddenContent (เนื้อหาตอนถูกซ่อน ใช้เทียบว่าแก้จริงไหม), hiddenNote, editRejectedAt
//
// โพสต์อยู่ 2 ที่: posts/{id} (หน้าแรก/เพจ) และ communities/{cid}/posts/{id} (ชุมชน/กลุ่ม)
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const {
  REPORT_HIDE_THRESHOLD,
  ACTIVE_REPORT_STATUSES,
  evaluateEdit,
  isHiddenNow,
} = require('./moderation_logic');

const SYSTEM_UID = 'system';
const TARGET_LABEL = {
  post: 'โพสต์',
  community_post: 'โพสต์ในชุมชน',
  profile: 'โปรไฟล์',
  comment: 'ความคิดเห็น',
  message: 'ข้อความแชท',
  group_message: 'ข้อความกลุ่ม',
  page: 'เพจ',
  community: 'ชุมชน',
  event: 'กิจกรรม',
};

const contentField = (scope) => (scope === 'community' ? 'text' : 'content');

function postRef(db, scope, communityId, postId) {
  return scope === 'community'
    ? db.collection('communities').doc(communityId).collection('posts').doc(postId)
    : db.collection('posts').doc(postId);
}

function snippet(text, n = 50) {
  const t = String(text || '').replace(/\s+/g, ' ').trim();
  if (!t) return 'โพสต์ของคุณ';
  return `"${Array.from(t).slice(0, n).join('')}${Array.from(t).length > n ? '…' : ''}"`;
}

// ---------------------------------------------------------------- แจ้งเตือน

/** เขียนแจ้งเตือนในแอป (users/{uid}/notifications) — sendUserPush จะส่ง push ต่อให้เอง */
async function notifyUser(db, toUid, n) {
  if (!toUid) return;
  await db.collection('users').doc(toUid).collection('notifications').add({
    fromUid: SYSTEM_UID,
    type: n.type,
    source: 'moderation',
    sourceId: n.communityId || null,
    sourceName: n.communityName || null,
    postId: n.postId || null,
    text: n.text || '',
    groupId: null,
    groupName: null,
    chatId: null,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  });
}

let adminCache = { at: 0, uids: [] };
/** รายชื่อแอดมิน = ผู้ใช้ที่มี custom claim admin (สแกนจาก Auth, แคช 5 นาที) */
async function getAdminUids() {
  if (Date.now() - adminCache.at < 5 * 60 * 1000) return adminCache.uids;
  const uids = [];
  let token;
  let pages = 0;
  do {
    const res = await getAuth().listUsers(1000, token);
    for (const u of res.users) if (u.customClaims?.admin === true) uids.push(u.uid);
    token = res.pageToken;
    pages++;
  } while (token && pages < 5);
  adminCache = { at: Date.now(), uids };
  return uids;
}

// ---------------------------------------------------------------- ซ่อน / เลิกซ่อน

async function setRelatedReports(db, report, status, reviewer) {
  const snap = await db
    .collection('reports')
    .where('targetType', '==', report.targetType)
    .where('targetId', '==', report.targetId)
    .get();
  const docs = snap.docs.filter((d) => {
    const x = d.data();
    return ACTIVE_REPORT_STATUSES.includes(x.status || 'open')
      && (report.targetType !== 'community_post' || x.contextId === report.contextId);
  });
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const d of docs.slice(i, i + 400)) {
      batch.update(d.ref, { status, reviewedBy: reviewer, reviewedAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
  }
}

const reportKey = (scope, communityId, postId) => ({
  targetType: scope === 'community' ? 'community_post' : 'post',
  targetId: postId,
  contextId: scope === 'community' ? communityId : '',
});

async function communityName(db, communityId) {
  if (!communityId) return null;
  return (await db.collection('communities').doc(communityId).get()).data()?.name || null;
}

/**
 * ซ่อนโพสต์
 * by = 'reports' (ถูกรายงานเกินกำหนด -> ซ่อนจนกว่าจะแก้ไข) | 'admin' (days > 0 = ซ่อนกี่วัน, 0 = จนกว่าจะแก้ไข)
 */
async function hidePost(db, { scope, communityId, postId, by, days = 0, note = '', adminUid = null }) {
  const ref = postRef(db, scope, communityId, postId);
  const snap = await ref.get();
  if (!snap.exists) return { ok: false, reason: 'not-found' };
  const data = snap.data();
  // ถูกรายงานซ้ำตอนซ่อนอยู่แล้ว ไม่ต้องทำซ้ำ/ไม่ต้องแจ้งเจ้าของซ้ำ
  if (by === 'reports' && isHiddenNow(data)) return { ok: true, already: true };

  const until = days > 0 ? Timestamp.fromMillis(Date.now() + days * 86400000) : null;
  const reason = by === 'reports'
    ? 'ถูกรายงานจากผู้ใช้หลายคน'
    : (note || 'ละเมิดกฎการใช้งาน');
  await ref.update({
    hidden: true,
    hiddenBy: by,
    hiddenReason: reason,
    hiddenAt: FieldValue.serverTimestamp(),
    hiddenUntil: until,
    hiddenContent: data[contentField(scope)] || '',
    hiddenNote: note || '',
    hiddenByUid: adminUid,
    editRejectedAt: FieldValue.delete(),
  });

  const text = by === 'reports'
    ? `${snippet(data[contentField(scope)])} ถูกซ่อนชั่วคราวเพราะถูกรายงานจากผู้ใช้หลายคน — แก้ไขโพสต์ให้เหมาะสม ระบบจะตรวจสอบและแสดงอีกครั้ง`
    : `แอดมินซ่อน ${snippet(data[contentField(scope)])}${days > 0 ? ` เป็นเวลา ${days} วัน` : ''}${note ? ` เหตุผล: ${note}` : ''} — แก้ไขโพสต์เพื่อให้ระบบตรวจสอบและแสดงอีกครั้ง`;
  await notifyUser(db, data.authorId, {
    type: 'post_hidden',
    text,
    postId,
    communityId: scope === 'community' ? communityId : null,
    communityName: scope === 'community' ? await communityName(db, communityId) : null,
  });
  // ซ่อนแล้ว = รายงานเรื่องนี้ถูกดำเนินการแล้ว (ไม่นับรวมรอบถัดไป)
  await setRelatedReports(db, reportKey(scope, communityId, postId), 'resolved', by === 'admin' ? adminUid || 'admin' : 'auto_hide');
  return { ok: true };
}

/** เลิกซ่อน — reason: 'edited' (เจ้าของแก้ไขจริง) | 'admin' (แอดมินเลิกซ่อน) */
async function unhidePost(db, { scope, communityId, postId, reason, adminUid = null }) {
  const ref = postRef(db, scope, communityId, postId);
  const snap = await ref.get();
  if (!snap.exists) return { ok: false, reason: 'not-found' };
  const data = snap.data();
  await ref.update({
    hidden: false,
    hiddenBy: FieldValue.delete(),
    hiddenReason: FieldValue.delete(),
    hiddenUntil: FieldValue.delete(),
    hiddenContent: FieldValue.delete(),
    hiddenNote: FieldValue.delete(),
    hiddenByUid: FieldValue.delete(),
    editRejectedAt: FieldValue.delete(),
    restoredAt: FieldValue.serverTimestamp(),
  });
  await setRelatedReports(db, reportKey(scope, communityId, postId), reason === 'edited' ? 'resolved' : 'dismissed', reason === 'edited' ? 'auto_edit' : adminUid || 'admin');
  await notifyUser(db, data.authorId, {
    type: 'post_restored',
    text: reason === 'edited'
      ? `ตรวจสอบแล้ว ${snippet(data[contentField(scope)])} แก้ไขเรียบร้อย โพสต์กลับมาแสดงอีกครั้ง`
      : `แอดมินตรวจสอบแล้ว ${snippet(data[contentField(scope)])} กลับมาแสดงอีกครั้ง`,
    postId,
    communityId: scope === 'community' ? communityId : null,
    communityName: scope === 'community' ? await communityName(db, communityId) : null,
  });
  return { ok: true };
}

// ---------------------------------------------------------------- รายงานใหม่

exports.onReportCreated = onDocumentCreated('reports/{reportId}', async (event) => {
  const r = event.data?.data();
  if (!r) return;
  const db = getFirestore();

  // 1) แจ้งแอดมินทุกคน (ยกเว้นผู้รายงานเอง ถ้าเขาเป็นแอดมิน)
  try {
    const admins = (await getAdminUids()).filter((uid) => uid !== r.reporterId);
    const label = TARGET_LABEL[r.targetType] || 'เนื้อหา';
    await Promise.all(admins.map((uid) => notifyUser(db, uid, {
      type: 'admin_report',
      text: `มีรายงาน${label}ใหม่: ${r.reason || 'ไม่ระบุเหตุผล'}`,
      postId: r.targetType === 'post' ? r.targetId : null,
    })));
  } catch (e) {
    console.error('notify admins failed', e);
  }

  // 2) นับผู้รายงานของโพสต์เดียวกัน ถ้าถึงเกณฑ์ -> ซ่อนอัตโนมัติ
  if (r.targetType !== 'post' && r.targetType !== 'community_post') return;
  const scope = r.targetType === 'community_post' ? 'community' : 'home';
  if (scope === 'community' && !r.contextId) return;
  const snap = await db
    .collection('reports')
    .where('targetType', '==', r.targetType)
    .where('targetId', '==', r.targetId)
    .get();
  const reporters = new Set(
    snap.docs
      .map((d) => d.data())
      .filter((x) => ACTIVE_REPORT_STATUSES.includes(x.status || 'open') && (scope === 'home' || x.contextId === r.contextId))
      .map((x) => x.reporterId),
  );
  if (reporters.size >= REPORT_HIDE_THRESHOLD) {
    await hidePost(db, { scope, communityId: r.contextId, postId: r.targetId, by: 'reports' });
  }
});

// รายงานโพสต์ในชุมชนถูกเก็บใน communities/{id}/reports (ผู้ดูแลชุมชนเห็น) -> คัดลอกไป reports/ ให้แอดมินเห็นและนับรวมด้วย
exports.mirrorCommunityReport = onDocumentCreated('communities/{communityId}/reports/{reportId}', async (event) => {
  const r = event.data?.data();
  if (!r || (r.targetType || 'post') !== 'post' || !r.postId || !r.reporterId) return;
  const { communityId } = event.params;
  await getFirestore()
    .collection('reports')
    .doc(`${r.reporterId}_community_post_${r.postId}`)
    .set({
      reporterId: r.reporterId,
      targetType: 'community_post',
      targetId: r.postId,
      reportedUid: r.reportedUid || '',
      contextId: communityId,
      reason: r.reason || '',
      details: r.details || '',
      status: 'open',
      createdAt: FieldValue.serverTimestamp(),
    });
});

// ---------------------------------------------------------------- ตรวจการแก้ไข

async function handlePostUpdated(event, scope) {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || after.hidden !== true) return;
  const field = contentField(scope);
  // ต้องเป็นการแก้ "เนื้อหา" เท่านั้น (ตอนซ่อน/เลิกซ่อน/แก้ audience เนื้อหาไม่เปลี่ยน -> ไม่วนลูป)
  if ((before[field] || '') === (after[field] || '')) return;

  const db = getFirestore();
  const { postId, communityId } = event.params;
  const original = after.hiddenContent ?? before[field] ?? '';
  const verdict = evaluateEdit(original, after[field] || '', { hasMedia: !!after.mediaUrl });
  if (verdict.ok) {
    await unhidePost(db, { scope, communityId, postId, reason: 'edited' });
    return;
  }
  await postRef(db, scope, communityId, postId).update({ editRejectedAt: FieldValue.serverTimestamp() });
  await notifyUser(db, after.authorId, {
    type: 'post_edit_rejected',
    text: `ตรวจสอบการแก้ไขแล้ว ยังไม่เพียงพอ: ${verdict.reason} — โพสต์ยังถูกซ่อนอยู่`,
    postId,
    communityId: scope === 'community' ? communityId : null,
    communityName: scope === 'community' ? await communityName(db, communityId) : null,
  });
}

exports.onPostEdited = onDocumentUpdated('posts/{postId}', (event) => handlePostUpdated(event, 'home'));
exports.onCommunityPostEdited = onDocumentUpdated(
  'communities/{communityId}/posts/{postId}',
  (event) => handlePostUpdated(event, 'community'),
);

// ---------------------------------------------------------------- แอดมินสั่งซ่อน/เลิกซ่อน

exports.moderatePost = onCall(async (request) => {
  if (request.auth?.token?.admin !== true) {
    throw new HttpsError('permission-denied', 'เฉพาะแอดมินเท่านั้น');
  }
  const { scope, communityId, postId, action, days, note } = request.data || {};
  if (!['home', 'community'].includes(scope)) throw new HttpsError('invalid-argument', 'scope ไม่ถูกต้อง');
  if (typeof postId !== 'string' || !postId || postId.includes('/')) throw new HttpsError('invalid-argument', 'postId ไม่ถูกต้อง');
  if (scope === 'community' && (typeof communityId !== 'string' || !communityId || communityId.includes('/'))) {
    throw new HttpsError('invalid-argument', 'communityId ไม่ถูกต้อง');
  }
  if (!['hide', 'unhide'].includes(action)) throw new HttpsError('invalid-argument', 'action ไม่ถูกต้อง');
  const nDays = Number.isInteger(days) ? days : 0;
  if (nDays < 0 || nDays > 365) throw new HttpsError('invalid-argument', 'จำนวนวันต้องอยู่ระหว่าง 0-365');
  const cleanNote = typeof note === 'string' ? note.trim().slice(0, 200) : '';

  const db = getFirestore();
  const args = { scope, communityId: communityId || '', postId, adminUid: request.auth.uid };
  const result = action === 'hide'
    ? await hidePost(db, { ...args, by: 'admin', days: nDays, note: cleanNote })
    : await unhidePost(db, { ...args, reason: 'admin' });
  if (!result.ok) throw new HttpsError('not-found', 'ไม่พบโพสต์นี้ (อาจถูกลบแล้ว)');
  return { ok: true };
});
