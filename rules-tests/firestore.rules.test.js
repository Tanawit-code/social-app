// ทดสอบ Firestore Security Rules ด้วย Firestore Emulator
// รัน: cd rules-tests && npm install && npm test   (ดูรายละเอียดใน README.md)
//
// โครงของแต่ละเทสต์: seed ข้อมูลด้วยสิทธิ์ผู้ดูแล (ข้าม rules) แล้วลองทำงานในฐานะผู้ใช้จริง
// assertSucceeds = rules ต้องอนุญาต / assertFails = rules ต้องปฏิเสธ (permission-denied)

const { describe, it, before, after, beforeEach } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  query,
  where,
  serverTimestamp,
  writeBatch,
  arrayUnion,
  arrayRemove,
  Timestamp,
} = require('firebase/firestore');

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-social-app',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

// ---------- ตัวช่วย ----------

const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const asAnon = () => testEnv.unauthenticatedContext().firestore();

/** เขียนข้อมูลโดยข้าม rules (ใช้เตรียมข้อมูลเริ่มต้นเท่านั้น) */
async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

function userDoc(following = []) {
  return {
    name: 'user',
    bio: '',
    photoUrl: '',
    coverUrl: '',
    followers: [],
    following,
    isPrivate: false,
    createdAt: Timestamp.now(),
  };
}

// alice ติดตาม bob, carol / bob, carol ติดตาม alice / dave, eve ไม่ติดตามใคร
beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(doc(db, 'users/alice'), userDoc(['bob', 'carol']));
    await setDoc(doc(db, 'users/bob'), userDoc(['alice']));
    await setDoc(doc(db, 'users/carol'), userDoc(['alice']));
    await setDoc(doc(db, 'users/dave'), userDoc([]));
    await setDoc(doc(db, 'users/eve'), userDoc([]));
  });
});

const DM = 'alice_bob';

async function seedDm() {
  await seed((db) =>
    setDoc(doc(db, `chats/${DM}`), {
      type: 'direct',
      participants: ['alice', 'bob'],
      lastMessage: '',
      lastAt: Timestamp.now(),
    }),
  );
}

async function seedGroup(participants = ['alice', 'bob', 'carol'], ownerId = 'alice') {
  await seed((db) =>
    setDoc(doc(db, 'chats/g1'), {
      type: 'group',
      name: 'กลุ่มทดสอบ',
      ownerId,
      participants,
      lastMessage: '',
      lastAt: Timestamp.now(),
    }),
  );
}

async function seedMessage(chatId, id, senderId, text = 'hi') {
  await seed((db) =>
    setDoc(doc(db, `chats/${chatId}/messages/${id}`), {
      senderId,
      text,
      createdAt: Timestamp.now(),
    }),
  );
}

const newMessage = (senderId, text = 'hello') => ({
  senderId,
  text,
  createdAt: serverTimestamp(),
});

// ======================================================================
describe('users', () => {
  it('ยังไม่ล็อกอิน อ่านโปรไฟล์ไม่ได้', async () => {
    await assertFails(getDoc(doc(asAnon(), 'users/alice')));
  });

  it('คนที่ล็อกอินแล้ว อ่านโปรไฟล์ทั่วไปได้', async () => {
    await assertSucceeds(getDoc(doc(asUser('eve'), 'users/alice')));
  });

  it('แก้ชื่อของตัวเองได้', async () => {
    await assertSucceeds(updateDoc(doc(asUser('alice'), 'users/alice'), { name: 'Alice' }));
  });

  it('แก้ชื่อของคนอื่นไม่ได้', async () => {
    await assertFails(updateDoc(doc(asUser('alice'), 'users/bob'), { name: 'hacked' }));
  });

  it('สร้างโปรไฟล์ที่มีฟิลด์แปลกปลอม (isAdmin) ไม่ได้', async () => {
    await assertFails(
      setDoc(doc(asUser('frank'), 'users/frank'), { ...userDoc(), isAdmin: true }),
    );
  });

  it('สร้างโปรไฟล์ของตัวเองด้วยฟิลด์ที่อนุญาตได้', async () => {
    await assertSucceeds(setDoc(doc(asUser('frank'), 'users/frank'), userDoc()));
  });

  it('collection ที่ไม่ได้ประกาศไว้ใน rules อ่านไม่ได้ (default deny)', async () => {
    await assertFails(getDoc(doc(asUser('alice'), 'secrets/x')));
  });
});

// ======================================================================
async function seedPost(id, authorId, extra = {}) {
  await seed((db) =>
    setDoc(doc(db, `posts/${id}`), {
      authorId,
      content: 'โพสต์ทดสอบ',
      audience: 'public',
      createdAt: Timestamp.now(),
      likeCount: 0,
      dislikeCount: 0,
      ...extra,
    }),
  );
}

const newPost = (authorId, extra = {}) => ({
  authorId,
  content: 'สวัสดี',
  audience: 'public',
  createdAt: serverTimestamp(),
  likeCount: 0,
  dislikeCount: 0,
  ...extra,
});

describe('posts', () => {
  it('สร้างโพสต์ของตัวเองได้', async () => {
    await assertSucceeds(setDoc(doc(asUser('alice'), 'posts/p1'), newPost('alice')));
  });

  it('โพสต์แทนคนอื่นไม่ได้ (ปลอม authorId)', async () => {
    await assertFails(setDoc(doc(asUser('alice'), 'posts/p1'), newPost('bob')));
  });

  it('โพสต์ที่มีฟิลด์แปลกปลอมไม่ได้', async () => {
    await assertFails(setDoc(doc(asUser('alice'), 'posts/p1'), newPost('alice', { isPinned: true })));
  });

  it('เริ่มต้นด้วยยอดไลก์ไม่เป็นศูนย์ไม่ได้', async () => {
    await assertFails(setDoc(doc(asUser('alice'), 'posts/p1'), newPost('alice', { likeCount: 999 })));
  });

  it('audience ที่ไม่รู้จักไม่ได้', async () => {
    await assertFails(setDoc(doc(asUser('alice'), 'posts/p1'), newPost('alice', { audience: 'everyone' })));
  });

  describe('หลายรูปในโพสต์เดียว', () => {
    const img = 'data:image/jpeg;base64,AAAA';

    it('รูปแรก + รูปเพิ่มอีก 3 รูปได้', async () => {
      await assertSucceeds(
        setDoc(
          doc(asUser('alice'), 'posts/p1'),
          newPost('alice', { mediaType: 'image', mediaUrl: img, moreMediaUrls: [img, img, img] }),
        ),
      );
    });

    it('รูปเพิ่มเกิน 3 รูปไม่ได้', async () => {
      await assertFails(
        setDoc(
          doc(asUser('alice'), 'posts/p1'),
          newPost('alice', { mediaType: 'image', mediaUrl: img, moreMediaUrls: [img, img, img, img] }),
        ),
      );
    });

    it('โพสต์วิดีโอห้ามมีรูปเพิ่ม', async () => {
      await assertFails(
        setDoc(
          doc(asUser('alice'), 'posts/p1'),
          newPost('alice', {
            mediaType: 'video',
            mediaUrl: 'https://res.cloudinary.com/x/video/upload/a.mp4',
            moreMediaUrls: [img],
          }),
        ),
      );
    });
  });

  describe('การมองเห็นโพสต์', () => {
    it('โพสต์สาธารณะ คนอื่นที่ล็อกอินแล้วอ่านได้', async () => {
      await seedPost('p1', 'alice');
      await assertSucceeds(getDoc(doc(asUser('eve'), 'posts/p1')));
    });

    it('ยังไม่ล็อกอิน อ่านโพสต์ไม่ได้', async () => {
      await seedPost('p1', 'alice');
      await assertFails(getDoc(doc(asAnon(), 'posts/p1')));
    });

    it('โพสต์เฉพาะเพื่อน คนที่ไม่ใช่เพื่อนอ่านไม่ได้', async () => {
      await seedPost('p1', 'alice', { audience: 'friends' });
      await assertFails(getDoc(doc(asUser('eve'), 'posts/p1')));
    });

    it('โพสต์ส่วนตัว อ่านได้เฉพาะเจ้าของ', async () => {
      await seedPost('p1', 'alice', { audience: 'private' });
      await assertSucceeds(getDoc(doc(asUser('alice'), 'posts/p1')));
      await assertFails(getDoc(doc(asUser('bob'), 'posts/p1')));
    });

    it('ถ้าเจ้าของบล็อกเรา อ่านโพสต์ของเขาไม่ได้', async () => {
      await seedPost('p1', 'alice');
      await seed((db) => setDoc(doc(db, 'users/alice/blocks/eve'), { createdAt: Timestamp.now() }));
      await assertFails(getDoc(doc(asUser('eve'), 'posts/p1')));
    });
  });

  describe('แก้ไข / ลบ', () => {
    it('เจ้าของแก้เนื้อหาโพสต์ได้', async () => {
      await seedPost('p1', 'alice');
      await assertSucceeds(updateDoc(doc(asUser('alice'), 'posts/p1'), { content: 'แก้แล้ว' }));
    });

    it('คนอื่นแก้เนื้อหาโพสต์ไม่ได้', async () => {
      await seedPost('p1', 'alice');
      await assertFails(updateDoc(doc(asUser('bob'), 'posts/p1'), { content: 'hacked' }));
    });

    it('แก้ยอดไลก์ตรงๆ โดยไม่มีรีแอคชันรองรับไม่ได้', async () => {
      await seedPost('p1', 'alice');
      await assertFails(updateDoc(doc(asUser('bob'), 'posts/p1'), { likeCount: 100 }));
    });

    it('เจ้าของลบโพสต์ได้ / คนอื่นลบไม่ได้', async () => {
      await seedPost('p1', 'alice');
      await assertFails(deleteDoc(doc(asUser('bob'), 'posts/p1')));
      await assertSucceeds(deleteDoc(doc(asUser('alice'), 'posts/p1')));
    });
  });

  describe('ความคิดเห็น', () => {
    const newComment = (authorId, text = 'เยี่ยมเลย') => ({
      authorId,
      text,
      createdAt: serverTimestamp(),
    });

    it('คอมเมนต์โพสต์ที่มองเห็นได้', async () => {
      await seedPost('p1', 'alice');
      await assertSucceeds(setDoc(doc(asUser('bob'), 'posts/p1/comments/c1'), newComment('bob')));
    });

    it('คอมเมนต์โดยปลอม authorId ไม่ได้', async () => {
      await seedPost('p1', 'alice');
      await assertFails(setDoc(doc(asUser('bob'), 'posts/p1/comments/c1'), newComment('alice')));
    });

    it('คอมเมนต์ว่างไม่ได้', async () => {
      await seedPost('p1', 'alice');
      await assertFails(setDoc(doc(asUser('bob'), 'posts/p1/comments/c1'), newComment('bob', '')));
    });

    it('คอมเมนต์โพสต์ส่วนตัวของคนอื่นไม่ได้', async () => {
      await seedPost('p1', 'alice', { audience: 'private' });
      await assertFails(setDoc(doc(asUser('bob'), 'posts/p1/comments/c1'), newComment('bob')));
    });
  });
});

// ======================================================================
describe('รีแอคชันโพสต์ (เขียนรีแอคชัน + ยอดนับพร้อมกันในครั้งเดียว)', () => {
  const reactionPath = 'posts/p1/reactions/bob';

  /** ทำเหมือนที่แอปทำ: เขียน/ลบเอกสารรีแอคชัน และอัปเดตยอดในโพสต์ใน batch เดียว */
  async function react({ set, remove, counts }) {
    const db = asUser('bob');
    const batch = writeBatch(db);
    if (set) batch.set(doc(db, reactionPath), { type: set });
    if (remove) batch.delete(doc(db, reactionPath));
    batch.update(doc(db, 'posts/p1'), counts);
    return batch.commit();
  }

  it('กดไลก์ครั้งแรก ยอดไลก์ +1', async () => {
    await seedPost('p1', 'alice');
    await assertSucceeds(react({ set: 'like', counts: { likeCount: 1, dislikeCount: 0 } }));
  });

  it('[บั๊กที่เจอ] กดไลก์ซ้ำเพื่อยกเลิก (ลบรีแอคชัน ยอดไลก์ -1) ต้องทำได้', async () => {
    await seedPost('p1', 'alice', { likeCount: 1 });
    await seed((db) => setDoc(doc(db, reactionPath), { type: 'like' }));
    await assertSucceeds(react({ remove: true, counts: { likeCount: 0, dislikeCount: 0 } }));
  });

  it('เปลี่ยนจากไลก์เป็นดิสไลก์ ยอดไลก์ -1 ดิสไลก์ +1', async () => {
    await seedPost('p1', 'alice', { likeCount: 1 });
    await seed((db) => setDoc(doc(db, reactionPath), { type: 'like' }));
    await assertSucceeds(react({ set: 'dislike', counts: { likeCount: 0, dislikeCount: 1 } }));
  });

  it('เปลี่ยนเป็นอีโมจิอื่น (love) ยอดไลก์ -1 ดิสไลก์เท่าเดิม', async () => {
    await seedPost('p1', 'alice', { likeCount: 1 });
    await seed((db) => setDoc(doc(db, reactionPath), { type: 'like' }));
    await assertSucceeds(react({ set: 'love', counts: { likeCount: 0, dislikeCount: 0 } }));
  });

  it('กดไลก์แต่ยอดเพิ่มมากกว่า 1 ไม่ได้', async () => {
    await seedPost('p1', 'alice');
    await assertFails(react({ set: 'like', counts: { likeCount: 5, dislikeCount: 0 } }));
  });

  it('ยกเลิกรีแอคชันแต่ไม่ลดยอดไม่ได้', async () => {
    await seedPost('p1', 'alice', { likeCount: 1 });
    await seed((db) => setDoc(doc(db, reactionPath), { type: 'like' }));
    await assertFails(react({ remove: true, counts: { likeCount: 1, dislikeCount: 0 } }));
  });

  it('เขียนรีแอคชันแทนคนอื่นไม่ได้', async () => {
    await seedPost('p1', 'alice');
    const db = asUser('bob');
    await assertFails(setDoc(doc(db, 'posts/p1/reactions/carol'), { type: 'like' }));
  });
});

// ======================================================================
describe('chats แบบ 1:1', () => {
  it('ยังไม่ล็อกอิน อ่านห้องแชทไม่ได้', async () => {
    await seedDm();
    await assertFails(getDoc(doc(asAnon(), `chats/${DM}`)));
  });

  it('[บั๊กที่เคยเจอ] เปิดห้องที่ยังไม่เคยสร้าง (get เอกสารที่ไม่มี) ต้องไม่ permission-denied', async () => {
    await assertSucceeds(getDoc(doc(asUser('alice'), `chats/${DM}`)));
  });

  it('สมาชิกในห้องอ่านห้องได้ / คนนอกอ่านไม่ได้', async () => {
    await seedDm();
    await assertSucceeds(getDoc(doc(asUser('alice'), `chats/${DM}`)));
    await assertFails(getDoc(doc(asUser('eve'), `chats/${DM}`)));
  });

  it('รายการแชทของตัวเอง (array-contains) query ได้ แต่ query ทุกห้องไม่ได้', async () => {
    await seedDm();
    await assertSucceeds(
      getDocs(query(collection(asUser('alice'), 'chats'), where('participants', 'array-contains', 'alice'))),
    );
    await assertFails(getDocs(collection(asUser('eve'), 'chats')));
  });

  it('สร้างห้อง 1:1 ที่ตัวเองเป็นสมาชิกได้', async () => {
    await assertSucceeds(
      setDoc(doc(asUser('alice'), `chats/${DM}`), {
        type: 'direct',
        participants: ['alice', 'bob'],
        lastMessage: '',
        lastAt: serverTimestamp(),
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('สร้างห้องที่ตัวเองไม่ได้เป็นสมาชิกไม่ได้', async () => {
    await assertFails(
      setDoc(doc(asUser('eve'), `chats/${DM}`), {
        type: 'direct',
        participants: ['alice', 'bob'],
        lastMessage: '',
        lastAt: serverTimestamp(),
      }),
    );
  });

  it('ห้อง direct ที่มี 3 คนไม่ได้', async () => {
    await assertFails(
      setDoc(doc(asUser('alice'), 'chats/x'), {
        type: 'direct',
        participants: ['alice', 'bob', 'carol'],
        lastMessage: '',
        lastAt: serverTimestamp(),
      }),
    );
  });

  it('สร้างห้องกับคนที่บล็อกกันไม่ได้', async () => {
    await seed((db) => setDoc(doc(db, 'users/bob/blocks/alice'), { createdAt: Timestamp.now() }));
    await assertFails(
      setDoc(doc(asUser('alice'), `chats/${DM}`), {
        type: 'direct',
        participants: ['alice', 'bob'],
        lastMessage: '',
        lastAt: serverTimestamp(),
      }),
    );
  });

  it('สมาชิกอัปเดต lastMessage / lastAt ได้', async () => {
    await seedDm();
    await assertSucceeds(
      updateDoc(doc(asUser('bob'), `chats/${DM}`), {
        lastMessage: 'hi',
        lastAt: serverTimestamp(),
      }),
    );
  });

  it('เพิ่มสมาชิกเข้าห้อง 1:1 ไม่ได้', async () => {
    await seedDm();
    await assertFails(
      updateDoc(doc(asUser('alice'), `chats/${DM}`), { participants: arrayUnion('eve') }),
    );
  });

  it('คนนอกอัปเดตห้องไม่ได้', async () => {
    await seedDm();
    await assertFails(
      updateDoc(doc(asUser('eve'), `chats/${DM}`), { lastMessage: 'x', lastAt: serverTimestamp() }),
    );
  });
});

// ======================================================================
describe('messages', () => {
  it('สมาชิกส่งข้อความได้', async () => {
    await seedDm();
    await assertSucceeds(setDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), newMessage('alice')));
  });

  it('ส่งข้อความโดยปลอม senderId ไม่ได้', async () => {
    await seedDm();
    await assertFails(setDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), newMessage('bob')));
  });

  it('ส่งข้อความด้วยเวลาจากเครื่อง (ไม่ใช่เวลาเซิร์ฟเวอร์) ไม่ได้', async () => {
    await seedDm();
    await assertFails(
      setDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), {
        senderId: 'alice',
        text: 'hi',
        createdAt: Timestamp.fromDate(new Date('2020-01-01')),
      }),
    );
  });

  it('ส่งข้อความว่าง (ไม่มีทั้งข้อความและรูป) ไม่ได้', async () => {
    await seedDm();
    await assertFails(
      setDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), {
        senderId: 'alice',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('ส่งข้อความที่มีฟิลด์เกินจากที่กำหนดไม่ได้', async () => {
    await seedDm();
    await assertFails(
      setDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), { ...newMessage('alice'), admin: true }),
    );
  });

  it('คนนอกอ่าน/ส่งข้อความในห้องไม่ได้', async () => {
    await seedDm();
    await seedMessage(DM, 'm1', 'alice');
    await assertFails(getDoc(doc(asUser('eve'), `chats/${DM}/messages/m1`)));
    await assertFails(setDoc(doc(asUser('eve'), `chats/${DM}/messages/m2`), newMessage('eve')));
  });

  it('สมาชิกอ่านข้อความได้', async () => {
    await seedDm();
    await seedMessage(DM, 'm1', 'alice');
    await assertSucceeds(getDoc(doc(asUser('bob'), `chats/${DM}/messages/m1`)));
  });

  it('ถ้าอีกฝ่ายบล็อกเราไว้ ส่งข้อความไม่ได้', async () => {
    await seedDm();
    await seed((db) => setDoc(doc(db, 'users/bob/blocks/alice'), { createdAt: Timestamp.now() }));
    await assertFails(setDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), newMessage('alice')));
  });

  describe('ลบข้อความ (soft delete)', () => {
    const softDelete = { deleted: true, text: null, imageUrl: null };

    it('เจ้าของข้อความลบได้', async () => {
      await seedDm();
      await seedMessage(DM, 'm1', 'alice');
      await assertSucceeds(updateDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), softDelete));
    });

    it('อีกฝ่ายลบข้อความของเราไม่ได้ (ห้อง 1:1 ไม่มีเจ้าของห้อง)', async () => {
      await seedDm();
      await seedMessage(DM, 'm1', 'alice');
      await assertFails(updateDoc(doc(asUser('bob'), `chats/${DM}/messages/m1`), softDelete));
    });

    it('แก้เนื้อหาข้อความเป็นอย่างอื่นไม่ได้', async () => {
      await seedDm();
      await seedMessage(DM, 'm1', 'alice');
      await assertFails(updateDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), { text: 'แก้แล้ว' }));
    });

    it('ตั้ง deleted แต่ไม่ล้างเนื้อหาเดิมไม่ได้', async () => {
      await seedDm();
      await seedMessage(DM, 'm1', 'alice');
      await assertFails(updateDoc(doc(asUser('alice'), `chats/${DM}/messages/m1`), { deleted: true }));
    });

    it('เจ้าของกลุ่มลบข้อความของสมาชิกได้', async () => {
      await seedGroup();
      await seedMessage('g1', 'm1', 'bob');
      await assertSucceeds(updateDoc(doc(asUser('alice'), 'chats/g1/messages/m1'), softDelete));
    });

    it('สมาชิกทั่วไปลบข้อความของคนอื่นในกลุ่มไม่ได้', async () => {
      await seedGroup();
      await seedMessage('g1', 'm1', 'bob');
      await assertFails(updateDoc(doc(asUser('carol'), 'chats/g1/messages/m1'), softDelete));
    });
  });
});

// ======================================================================
describe('chatStates (ลบแชท / ลบประวัติแชท รายคน)', () => {
  const statePath = (uid) => `users/${uid}/chatStates/${DM}`;

  it('เขียนสถานะของตัวเองได้', async () => {
    await assertSucceeds(
      setDoc(doc(asUser('alice'), statePath('alice')), {
        clearedAt: serverTimestamp(),
        deletedAt: serverTimestamp(),
      }),
    );
  });

  it('เขียน/อ่านสถานะของคนอื่นไม่ได้', async () => {
    await assertFails(setDoc(doc(asUser('bob'), statePath('alice')), { clearedAt: serverTimestamp() }));
    await seed((db) => setDoc(doc(db, statePath('alice')), { clearedAt: Timestamp.now() }));
    await assertFails(getDoc(doc(asUser('bob'), statePath('alice'))));
  });

  it('ใส่ฟิลด์แปลกปลอมไม่ได้', async () => {
    await assertFails(setDoc(doc(asUser('alice'), statePath('alice')), { clearedAt: serverTimestamp(), foo: 1 }));
  });

  it('ค่าที่ไม่ใช่ timestamp ไม่ได้', async () => {
    await assertFails(setDoc(doc(asUser('alice'), statePath('alice')), { clearedAt: 'เมื่อวาน' }));
  });

  it('ลบสถานะของตัวเองได้', async () => {
    await seed((db) => setDoc(doc(db, statePath('alice')), { clearedAt: Timestamp.now() }));
    await assertSucceeds(deleteDoc(doc(asUser('alice'), statePath('alice'))));
  });
});

// ======================================================================
describe('กลุ่มแชท', () => {
  const groupData = (ownerId, participants) => ({
    type: 'group',
    name: 'กลุ่มใหม่',
    ownerId,
    participants,
    lastMessage: 'สร้างกลุ่มแล้ว',
    lastAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  });

  describe('สร้างกลุ่ม', () => {
    it('สร้างกลุ่มกับคนที่ตัวเองติดตามได้', async () => {
      await assertSucceeds(setDoc(doc(asUser('alice'), 'chats/new'), groupData('alice', ['alice', 'bob'])));
    });

    it('ใส่คนที่ตัวเองไม่ได้ติดตามไม่ได้', async () => {
      await assertFails(setDoc(doc(asUser('alice'), 'chats/new'), groupData('alice', ['alice', 'dave'])));
    });

    it('ตั้งคนอื่นเป็นเจ้าของกลุ่มไม่ได้', async () => {
      await assertFails(setDoc(doc(asUser('eve'), 'chats/new'), groupData('alice', ['eve', 'alice'])));
    });
  });

  describe('ออกจากกลุ่ม / เตะ', () => {
    it('สมาชิกทั่วไปออกจากกลุ่มเองได้', async () => {
      await seedGroup();
      await assertSucceeds(updateDoc(doc(asUser('bob'), 'chats/g1'), { participants: arrayRemove('bob') }));
    });

    it('สมาชิกทั่วไปเตะคนอื่นไม่ได้', async () => {
      await seedGroup();
      await assertFails(updateDoc(doc(asUser('bob'), 'chats/g1'), { participants: arrayRemove('carol') }));
    });

    it('เจ้าของเตะสมาชิกได้', async () => {
      await seedGroup();
      await assertSucceeds(updateDoc(doc(asUser('alice'), 'chats/g1'), { participants: arrayRemove('carol') }));
    });

    it('เจ้าของออกจากกลุ่มโดยไม่โอนความเป็นเจ้าของไม่ได้', async () => {
      await seedGroup();
      await assertFails(updateDoc(doc(asUser('alice'), 'chats/g1'), { participants: arrayRemove('alice') }));
    });

    it('เจ้าของออกพร้อมโอนความเป็นเจ้าของให้สมาชิกที่เหลือได้', async () => {
      await seedGroup();
      await assertSucceeds(
        updateDoc(doc(asUser('alice'), 'chats/g1'), {
          participants: arrayRemove('alice'),
          ownerId: 'bob',
        }),
      );
    });

    it('เจ้าของโอนกลุ่มให้คนที่ไม่ได้อยู่ในกลุ่มไม่ได้', async () => {
      await seedGroup();
      await assertFails(
        updateDoc(doc(asUser('alice'), 'chats/g1'), {
          participants: arrayRemove('alice'),
          ownerId: 'eve',
        }),
      );
    });

    it('เตะสมาชิกทีละหลายคนในครั้งเดียวไม่ได้', async () => {
      await seedGroup(['alice', 'bob', 'carol', 'dave']);
      await assertFails(
        updateDoc(doc(asUser('alice'), 'chats/g1'), { participants: arrayRemove('bob', 'carol') }),
      );
    });

    it('คนที่ถูกเตะออกแล้วอ่านข้อความของกลุ่มไม่ได้', async () => {
      await seedGroup(['alice', 'bob']);
      await seedMessage('g1', 'm1', 'alice');
      await assertFails(getDoc(doc(asUser('carol'), 'chats/g1/messages/m1')));
    });
  });

  describe('เพิ่มเพื่อนเข้ากลุ่ม', () => {
    it('เจ้าของเพิ่มคนที่ตัวเองติดตามได้', async () => {
      await seedGroup(['alice', 'bob']);
      await assertSucceeds(updateDoc(doc(asUser('alice'), 'chats/g1'), { participants: arrayUnion('carol') }));
    });

    it('เจ้าของเพิ่มคนที่ตัวเองไม่ได้ติดตามไม่ได้', async () => {
      await seedGroup(['alice', 'bob']);
      await assertFails(updateDoc(doc(asUser('alice'), 'chats/g1'), { participants: arrayUnion('dave') }));
    });

    it('สมาชิกทั่วไปเพิ่มคนเข้ากลุ่มไม่ได้', async () => {
      await seedGroup(['alice', 'bob']);
      await assertFails(updateDoc(doc(asUser('bob'), 'chats/g1'), { participants: arrayUnion('carol') }));
    });

    it('คนนอกกลุ่มเพิ่มตัวเองเข้ากลุ่มไม่ได้', async () => {
      await seedGroup(['alice', 'bob']);
      await assertFails(updateDoc(doc(asUser('eve'), 'chats/g1'), { participants: arrayUnion('eve') }));
    });

    it('สมาชิกรวมเกิน 50 คนไม่ได้', async () => {
      // alice ติดตาม dave เพิ่ม เพื่อให้ผิดเฉพาะเรื่องจำนวน ไม่ใช่เรื่องการติดตาม
      await seed((db) => setDoc(doc(db, 'users/alice'), userDoc(['bob', 'carol', 'dave'])));
      const fifty = ['alice', ...Array.from({ length: 49 }, (_, i) => `u${i}`)];
      await seedGroup(fifty);
      await assertFails(updateDoc(doc(asUser('alice'), 'chats/g1'), { participants: arrayUnion('dave') }));
    });
  });

  describe('ตั้งค่ากลุ่ม', () => {
    it('เจ้าของเปลี่ยนชื่อกลุ่มได้', async () => {
      await seedGroup();
      await assertSucceeds(updateDoc(doc(asUser('alice'), 'chats/g1'), { name: 'ชื่อใหม่' }));
    });

    it('สมาชิกทั่วไปเปลี่ยนชื่อกลุ่มไม่ได้', async () => {
      await seedGroup();
      await assertFails(updateDoc(doc(asUser('bob'), 'chats/g1'), { name: 'ชื่อใหม่' }));
    });

    it('เจ้าของลบกลุ่มได้ / สมาชิกทั่วไปลบไม่ได้', async () => {
      await seedGroup();
      await assertFails(deleteDoc(doc(asUser('bob'), 'chats/g1')));
      await assertSucceeds(deleteDoc(doc(asUser('alice'), 'chats/g1')));
    });
  });
});