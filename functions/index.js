const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

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
      notification.fromUid ? db.collection('users').doc(notification.fromUid).get() : null,
    ]);
    const account = accountSnap.data() || {};
    if (account.pushEnabled !== true || tokenSnap.empty) return;
    if (notification.type === 'message' && account.messageNotifications === false) return;
    if (notification.type !== 'message' && account.socialNotifications === false) return;

    const senderName = senderSnap?.data()?.name || 'มีคน';
    const title = notification.type === 'message' ? 'ข้อความใหม่' : 'การแจ้งเตือนใหม่';
    const body = notification.type === 'message'
      ? `${senderName} ส่งข้อความถึงคุณ`
      : (notification.text || `${senderName} มีกิจกรรมกับบัญชีของคุณ`);
    const tokens = tokenSnap.docs.map((doc) => ({ id: doc.id, token: doc.data().token })).filter((item) => item.token);
    if (tokens.length === 0) return;

    const response = await getMessaging().sendEachForMulticast({
      tokens: tokens.map((item) => item.token),
      notification: { title, body },
      data: { route: '/notifications', type: String(notification.type || 'activity') },
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
