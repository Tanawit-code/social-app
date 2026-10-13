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
  }) async {
    if (toUid.isEmpty || toUid == fromUid) return; // ไม่แจ้งเตือนตัวเอง
    await _col(toUid).add({
      'fromUid': fromUid,
      'type': type,
      'postId': postId,
      'text': text,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> stream(String uid) {
    return _col(uid).orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  Stream<int> unreadCount(String uid) {
    return _col(uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  Future<void> markAllRead(String uid) async {
    final snap = await _col(uid).where('isRead', isEqualTo: false).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'isRead': true});
    }
    await batch.commit();
  }
}
