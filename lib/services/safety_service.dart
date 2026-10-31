import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

int _boundedLength(String value, int max) => value.length > max ? max : value.length;

/// User initiated safety controls. Reports are write-only to clients; only
/// privileged server tooling should be able to review them.
class SafetyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get currentUid => AuthService().currentUser?.uid ?? '';

  Stream<bool> isBlockedByMe(String uid) {
    final me = currentUid;
    if (me.isEmpty || uid.isEmpty) return Stream.value(false);
    return _db.collection('users').doc(me).collection('blocks').doc(uid)
        .snapshots().map((doc) => doc.exists);
  }

  Future<void> block(String uid) async {
    final me = currentUid;
    if (me.isEmpty || uid.isEmpty || me == uid) throw StateError('บัญชีไม่ถูกต้อง');
    final blockRef = _db.collection('users').doc(me).collection('blocks').doc(uid);
    await blockRef.set({'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> unblock(String uid) async {
    final me = currentUid;
    if (me.isEmpty || uid.isEmpty) throw StateError('บัญชีไม่ถูกต้อง');
    await _db.collection('users').doc(me).collection('blocks').doc(uid).delete();
  }

  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    final reporterId = currentUid;
    if (reporterId.isEmpty) throw StateError('กรุณาเข้าสู่ระบบ');
    const allowed = {'post', 'profile', 'comment', 'message', 'page'};
    if (!allowed.contains(targetType) || targetId.isEmpty) {
      throw ArgumentError('ข้อมูลรายงานไม่ถูกต้อง');
    }
    final ref = _db.collection('reports').doc();
    await ref.set({
      'reporterId': reporterId,
      'targetType': targetType,
      'targetId': targetId,
      'reason': reason.trim().substring(0, _boundedLength(reason.trim(), 80)),
      'details': details.trim().substring(0, _boundedLength(details.trim(), 500)),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
