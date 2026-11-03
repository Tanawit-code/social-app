import 'package:cloud_functions/cloud_functions.dart';

/// สั่งซ่อน/เลิกซ่อนโพสต์ (เฉพาะแอดมิน — ฝั่งเซิร์ฟเวอร์ตรวจ custom claim `admin` อีกชั้น)
/// ผ่าน Cloud Function `moderatePost`; เจ้าของโพสต์จะได้แจ้งเตือนอัตโนมัติ
class ModerationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// [communityId] ใส่เมื่อเป็นโพสต์ในชุมชน/กลุ่ม (ไม่ใส่ = โพสต์หน้าแรก/เพจ)
  /// [days] 0 = ซ่อนจนกว่าเจ้าของจะแก้ไข, > 0 = ซ่อนกี่วัน (แก้ไขจริงระหว่างนั้นก็กลับมาแสดงก่อนได้)
  Future<void> hidePost({
    required String postId,
    String? communityId,
    int days = 0,
    String note = '',
  }) => _call({
    'action': 'hide',
    'postId': postId,
    'communityId': communityId,
    'days': days,
    'note': note,
  });

  Future<void> unhidePost({required String postId, String? communityId}) =>
      _call({'action': 'unhide', 'postId': postId, 'communityId': communityId});

  Future<void> _call(Map<String, dynamic> data) async {
    final communityId = data['communityId'] as String?;
    try {
      await _functions.httpsCallable('moderatePost').call({
        ...data,
        'scope': communityId == null || communityId.isEmpty
            ? 'home'
            : 'community',
        'communityId': communityId ?? '',
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }
}
