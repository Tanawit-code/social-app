import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';

int _boundedLength(String value, int max) =>
    value.length > max ? max : value.length;

/// User initiated safety controls. Reports are write-only to clients; only
/// privileged server tooling should be able to review them.
class SafetyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get currentUid => AuthService().currentUser?.uid ?? '';

  Stream<bool> isBlockedByMe(String uid) {
    final me = currentUid;
    if (me.isEmpty || uid.isEmpty) return Stream.value(false);
    return _db
        .collection('users')
        .doc(me)
        .collection('blocks')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Future<void> block(String uid) async {
    final me = currentUid;
    if (me.isEmpty || uid.isEmpty || me == uid)
      throw StateError('บัญชีไม่ถูกต้อง');
    final blockRef = _db
        .collection('users')
        .doc(me)
        .collection('blocks')
        .doc(uid);
    await blockRef.set({'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> unblock(String uid) async {
    final me = currentUid;
    if (me.isEmpty || uid.isEmpty) throw StateError('บัญชีไม่ถูกต้อง');
    await _db
        .collection('users')
        .doc(me)
        .collection('blocks')
        .doc(uid)
        .delete();
  }

  /// แอดมิน = ผู้ใช้ที่มี custom claim `admin: true` (ตั้งด้วย tools/set_admin.mjs)
  static Future<bool> isAdmin() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult();
      return token?.claims?['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  /// ส่งรายงานไปที่ reports/ (ให้แอดมินตรวจ)
  /// - id ของเอกสาร = {reporter}_{targetType}_{targetId} จึงรายงานซ้ำรายการเดิมไม่ได้
  ///   (rules บังคับรูปแบบ id นี้ด้วย)
  /// - reportedUid = เจ้าของเนื้อหาที่ถูกรายงาน ช่วยให้แอดมินไล่ดูประวัติของบัญชีนี้ได้
  /// - contextId = id ห้องแชท/กลุ่ม/ชุมชนที่เนื้อหานั้นอยู่
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
    String reportedUid = '',
    String contextId = '',
  }) async {
    final reporterId = currentUid;
    if (reporterId.isEmpty) throw StateError('กรุณาเข้าสู่ระบบ');
    if (!reportTargetTypes.contains(targetType) ||
        targetId.isEmpty ||
        targetId.contains('/')) {
      throw ArgumentError('ข้อมูลรายงานไม่ถูกต้อง');
    }
    final ref = _db
        .collection('reports')
        .doc('${reporterId}_${targetType}_$targetId');
    try {
      await ref.set({
        'reporterId': reporterId,
        'targetType': targetType,
        'targetId': targetId,
        'reportedUid': reportedUid,
        'contextId': contextId,
        'reason': reason.trim().substring(0, _boundedLength(reason.trim(), 80)),
        'details': details.trim().substring(
          0,
          _boundedLength(details.trim(), 500),
        ),
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      // ผู้รายงานอ่าน reports ไม่ได้ จึงแยกไม่ได้ว่าซ้ำหรือสิทธิ์ผิด — ส่วนใหญ่คือรายงานซ้ำ
      if (e.code == 'permission-denied') throw const AlreadyReportedException();
      rethrow;
    }
  }
}

/// ชนิดเป้าหมายที่รายงานได้ (ต้องตรงกับ validReport() ใน firestore.rules)
const reportTargetTypes = {
  'post',
  'profile',
  'comment',
  'message',
  'page',
  'community',
  'group_message',
  'event',
};

/// เหตุผลมาตรฐานของการรายงาน ใช้ร่วมกันทุกที่
const reportReasons = [
  'สแปม',
  'เนื้อหาไม่เหมาะสม',
  'คุกคามหรือทำร้ายผู้อื่น',
  'ข้อมูลเท็จหรือหลอกลวง',
  'อื่นๆ',
];

class AlreadyReportedException implements Exception {
  const AlreadyReportedException();
  @override
  String toString() => 'คุณรายงานรายการนี้ไปแล้ว ทีมงานกำลังตรวจสอบ';
}
