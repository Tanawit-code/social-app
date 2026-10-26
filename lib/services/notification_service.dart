import 'package:cloud_firestore/cloud_firestore.dart';

/// แจ้งเตือนแบบ in-app เก็บที่ users/{uid}/notifications
/// type: 'like' | 'comment' | 'message'
class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  Future<void> create({
    required String toUid,
    required String fromUid,
    required String type,
    String? postId,
    String? text,
    String? groupId,
    String? groupName,
    String? chatId,
  }) async {
    if (toUid.isEmpty || toUid == fromUid) return; // ไม่แจ้งเตือนตัวเอง
    await _col(toUid).add({
      'fromUid': fromUid,
      'type': type,
      'postId': postId,
      'text': text,
      'groupId': groupId,
      'groupName': groupName,
      'chatId': chatId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> stream(String uid) {
    return _col(
      uid,
    ).orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  /// จำนวนที่ยังไม่อ่าน แยกเป็น 2 กลุ่ม
  /// messages: true  = แจ้งเตือนข้อความแชท (แสดงที่ไอคอนแชท)
  /// messages: false = อย่างอื่น เช่น ติดตาม/ไลก์/คอมเมนต์ (แสดงที่ไอคอนกระดิ่ง)
  /// นับฝั่ง client จาก query เดียว จึงไม่ต้องสร้าง index เพิ่มใน Firestore
  Stream<int> unreadCount(String uid, {required bool messages}) {
    return _col(uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map(
          (s) => s.docs
              .where((d) => (d.data()['type'] == 'message') == messages)
              .length,
        );
  }

  Stream<int> groupUnreadCount(String uid, String groupId) {
    return _col(uid)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) => snap.docs.where((doc) => doc.data()['isRead'] != true).length);
  }

  Stream<int> chatUnreadCount(String uid, String chatId) {
    return _col(uid)
        .where('chatId', isEqualTo: chatId)
        .snapshots()
        .map((snap) => snap.docs.where((doc) => doc.data()['isRead'] != true).length);
  }

  Future<void> markGroupRead(String uid, String groupId) async {
    final snap = await _col(uid).where('groupId', isEqualTo: groupId).get();
    final unread = snap.docs.where((doc) => doc.data()['isRead'] != true).toList();
    for (var i = 0; i < unread.length; i += 450) {
      final batch = _db.batch();
      for (final doc in unread.skip(i).take(450)) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }
  }

  Future<void> markChatRead(String uid, String chatId) async {
    final snap = await _col(uid).where('chatId', isEqualTo: chatId).get();
    final unread = snap.docs.where((doc) => doc.data()['isRead'] != true).toList();
    for (var i = 0; i < unread.length; i += 450) {
      final batch = _db.batch();
      for (final doc in unread.skip(i).take(450)) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }
  }

  /// ทำเครื่องหมายอ่านแล้วเฉพาะกลุ่ม (ข้อความแชท หรือ อย่างอื่น)
  Future<void> markRead(String uid, {required bool messages}) async {
    final snap = await _col(uid).where('isRead', isEqualTo: false).get();
    final targets = snap.docs
        .where((d) => (d.data()['type'] == 'message') == messages)
        .toList();
    if (targets.isEmpty) return;
    final batch = _db.batch();
    for (final d in targets) {
      batch.update(d.reference, {'isRead': true});
    }
    await batch.commit();
  }
}
