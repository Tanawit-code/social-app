const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

exports.checkEmailForReset = require('./password_reset').checkEmailForReset;

// ระบบรายงาน/ซ่อนโพสต์/ตรวจการแก้ไข (functions/moderation.js)
Object.assign(exports, require('./moderation'));


exports.checkEmailForReset = require('./password_reset').checkEmailForReset;

// ระบบรายงาน/ซ่อนโพสต์/ตรวจการแก้ไข (functions/moderation.js)
Object.assign(exports, require('./moderation'));

// ข้อความ push ตามชนิดแจ้งเตือน — ให้ตรงกับหน้าแจ้งเตือนในแอป (lib/screens/notifications_screen.dart)
const SOURCE_LABEL = {
  post: 'โพสต์',
  friend: 'เพื่อน',
  follow: 'ผู้ติดตาม',
  chat: 'แชท',
  community: 'ชุมชน',
  page: 'เพจ',
  moderation: 'การดูแลระบบ',
};
const ACTION_TEXT = {
  like: 'ถูกใจโพสต์ของคุณ',
  comment: 'แสดงความคิดเห็นในโพสต์ของคุณ',
  message: 'ส่งข้อความถึงคุณ',
  follow: 'เริ่มติดตามคุณ',
  follow_request: 'ส่งคำขอติดตามบัญชีส่วนตัวของคุณ',
  friend_request: 'ส่งคำขอเป็นเพื่อนถึงคุณ',
  friend_accepted: 'ตอบรับเป็นเพื่อนกับคุณ',
  community_join_request: 'ขอเข้าร่วมชุมชนของคุณ',
  community_join_approved: 'อนุมัติให้คุณเข้าร่วมชุมชนแล้ว',
  community_join_declined: 'ปฏิเสธคำขอเข้าร่วมชุมชนของคุณ',
  page_join_request: 'ขอเข้าร่วมเพจของคุณ',
  page_join_approved: 'อนุมัติให้คุณเข้าร่วมเพจแล้ว',
  page_join_declined: 'ปฏิเสธคำขอเข้าร่วมเพจของคุณ',
  admin_report: 'มีรายงานใหม่รอตรวจสอบ',
  post_hidden: 'โพสต์ของคุณถูกซ่อน',
  post_restored: 'โพสต์ของคุณกลับมาแสดงแล้ว',
  post_edit_rejected: 'การแก้ไขโพสต์ยังไม่เพียงพอ',
};
const SOURCE_BY_TYPE = {
  like: 'post', comment: 'post', message: 'chat', follow: 'follow', follow_request: 'follow',
  friend_request: 'friend', friend_accepted: 'friend',
  community_join_request: 'community', community_join_approved: 'community', community_join_declined: 'community',
  page_join_request: 'page', page_join_approved: 'page', page_join_declined: 'page',
};

exports.sendUserPush = onDocumentCreated(
  'users/{uid}/notifications/{notificationId}',
  async (event) => {
    const { uid } = event.params;
    const notification = event.data?.data();
    if (!notification) return;

    const db = getFirestore();
    const userRef = db.collection('users').doc(uid);
    const [accountSnap, tokenSnap, senderSnap] = await Promise.all([
      userRef.collection('private').doc('account').get(),
      userRef.collection('deviceTokens').get(),
      notification.fromUid && notification.fromUid !== 'system' ? db.collection('users').doc(notification.fromUid).get() : null,
    ]);
    const account = accountSnap.data() || {};
    if (account.pushEnabled !== true || tokenSnap.empty) return;
    if (notification.type === 'message' && account.messageNotifications === false) return;
    if (notification.type !== 'message' && account.socialNotifications === false) return;

    const senderName = senderSnap?.data()?.name || 'มีคน';
    const source = notification.source || SOURCE_BY_TYPE[notification.type] || 'post';
    const sourceLabel = SOURCE_LABEL[source] || 'การแจ้งเตือน';
    // หัวข้อบอกว่ามาจากไหน เช่น "ชุมชน · ชื่อชุมชน"
    const title = notification.type === 'message'
      ? 'ข้อความใหม่'
      : (notification.sourceName ? `${sourceLabel} · ${notification.sourceName}` : sourceLabel);
    const action = ACTION_TEXT[notification.type] || 'มีกิจกรรมกับบัญชีของคุณ';
    // แจ้งเตือนจากระบบ (ดูแลโพสต์) ไม่มีผู้ส่ง — ใช้ข้อความที่ระบบเขียนไว้เลย
    const body = notification.fromUid === 'system'
      ? (notification.text || action)
      : notification.type === 'comment' && notification.text
        ? `${senderName} ${action}: ${notification.text}`
        : `${senderName} ${action}`;
    const tokens = tokenSnap.docs.map((doc) => ({ id: doc.id, token: doc.data().token })).filter((item) => item.token);
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens: tokens.map((item) => item.token),
      notification: { title, body },
      // ค่าใน data ของ FCM ต้องเป็น string เท่านั้น (ห้าม null) — แอปใช้ฟิลด์เหล่านี้เปิดห้องแชทตรงๆ
      data: {
        route: '/notifications',
        type: String(notification.type || 'activity'),
        source: String(source),
        sourceId: String(notification.sourceId || ''),
        fromUid: String(notification.fromUid || ''),
        chatId: String(notification.chatId || ''),
        groupId: String(notification.groupId || ''),
      },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    const invalid = [];
    response.responses.forEach((result, index) => {
      if (!result.success && ['messaging/invalid-registration-token', 'messaging/registration-token-not-registered'].includes(result.error?.code)) {
        invalid.push(tokenSnap.docs.find((doc) => doc.id === tokens[index].id)?.ref);
      }
    });
    await Promise.all(invalid.filter(Boolean).map((ref) => ref.delete()));
  },
);