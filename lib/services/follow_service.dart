import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

/// ติดตาม / เลิกติดตาม
/// users/{me}.following  และ  users/{target}.followers  เป็น array ของ uid
/// อัปเดตสองเอกสารพร้อมกันด้วย batch (สำเร็จทั้งคู่หรือไม่สำเร็จเลย)
class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> follow({required String me, required String target}) async {
    if (me.isEmpty || target.isEmpty || me == target) return;
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
  }

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
