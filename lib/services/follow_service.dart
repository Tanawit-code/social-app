import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

/// ติดตาม / เลิกติดตาม
/// users/{me}.following  และ  users/{target}.followers  เป็น array ของ uid
/// อัปเดตสองเอกสารพร้อมกันด้วย batch (สำเร็จทั้งคู่หรือไม่สำเร็จเลย)
class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<bool> follow({required String me, required String target}) async {
    if (me.isEmpty || target.isEmpty || me == target) return false;
    final targetRef = _db.collection('users').doc(target);
    final targetSnapshot = await targetRef.get();
    if (!targetSnapshot.exists) throw Exception('ไม่พบบัญชีนี้');
    if (targetSnapshot.data()?['isPrivate'] == true) {
      final requestRef = targetRef.collection('followRequests').doc(me);
      final existing = await requestRef.get();
      if (!existing.exists) {
        await requestRef.set({
          'senderId': me,
          'createdAt': FieldValue.serverTimestamp(),
        });
        try {
          await NotificationService().create(
            toUid: target,
            fromUid: me,
            type: 'follow_request',
          );
        } catch (_) {}
      }
      return true;
    }
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(me), {
      'following': FieldValue.arrayUnion([target]),
    });
    batch.update(_db.collection('users').doc(target), {
      'followers': FieldValue.arrayUnion([me]),
    });
    await batch.commit();

    // แจ้งเตือนล้มเหลวไม่ควรทำให้การติดตามล้มเหลวตามไปด้วย
    try {
      await NotificationService().create(
        toUid: target,
        fromUid: me,
        type: 'follow',
      );
    } catch (_) {}
    return false;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> requests(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('followRequests')
      .orderBy('createdAt', descending: true)
      .snapshots();

  Future<void> acceptRequest({
    required String owner,
    required String requester,
  }) async {
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(owner), {
      'followers': FieldValue.arrayUnion([requester]),
      'lastApprovedFollower': requester,
    });
    batch.update(_db.collection('users').doc(requester), {
      'following': FieldValue.arrayUnion([owner]),
    });
    batch.delete(
      _db
          .collection('users')
          .doc(owner)
          .collection('followRequests')
          .doc(requester),
    );
    await batch.commit();
  }

  Future<void> declineRequest({
    required String owner,
    required String requester,
  }) => _db
      .collection('users')
      .doc(owner)
      .collection('followRequests')
      .doc(requester)
      .delete();

  Future<void> cancelRequest({
    required String requester,
    required String owner,
  }) => _db
      .collection('users')
      .doc(owner)
      .collection('followRequests')
      .doc(requester)
      .delete();

  Future<void> unfollow({required String me, required String target}) async {
    if (me.isEmpty || target.isEmpty || me == target) return;
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(me), {
      'following': FieldValue.arrayRemove([target]),
    });
    batch.update(_db.collection('users').doc(target), {
      'followers': FieldValue.arrayRemove([me]),
    });
    await batch.commit();
  }
}
