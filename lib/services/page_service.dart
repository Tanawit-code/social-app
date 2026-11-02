import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class PageService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _pages =>
      _db.collection('pages');

  Stream<QuerySnapshot<Map<String, dynamic>>> pages() =>
      _pages.orderBy('createdAt', descending: true).limit(200).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> page(String pageId) =>
      _pages.doc(pageId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> posts(String pageId) =>
      _db.collection('posts').where('pageId', isEqualTo: pageId).snapshots();

  Future<String> createPage({
    required String ownerId,
    required String name,
    required String description,
    required String privacy,
    String? photoUrl,
  }) async {
    if (ownerId.isEmpty || name.trim().isEmpty)
      throw Exception('กรุณาระบุชื่อเพจและเข้าสู่ระบบ');
    if (privacy != 'public' && privacy != 'private')
      throw Exception('รูปแบบการมองเห็นเพจไม่ถูกต้อง');
    final ref = _pages.doc();
    await ref.set({
      'name': name.trim(),
      'description': description.trim(),
      'ownerId': ownerId,
      'privacy': privacy,
      'photoUrl': photoUrl ?? '',
      'memberIds': [ownerId],
      'pendingRequests': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updatePagePhoto({
    required String pageId,
    required String ownerId,
    required String photoUrl,
  }) async {
    final ref = _pages.doc(pageId);
    final snap = await ref.get();
    if (!snap.exists || snap.data()?['ownerId'] != ownerId) {
      throw Exception('เฉพาะเจ้าของเพจเท่านั้นที่เปลี่ยนรูปได้');
    }
    await ref.update({'photoUrl': photoUrl});
  }

  Future<void> joinPublicPage(String pageId, String uid) async {
    final ref = _pages.doc(pageId);
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || data?['privacy'] != 'public')
        throw Exception('เพจนี้ไม่ได้เปิดเป็นสาธารณะ');
      transaction.update(ref, {
        'memberIds': FieldValue.arrayUnion([uid]),
      });
    });
  }

  /// แจ้งเตือนที่ผูกกับเพจ — ความล้มเหลวของแจ้งเตือนต้องไม่ทำให้ action หลักล้มเหลว
  Future<void> _notify({
    required String pageId,
    required String pageName,
    required String toUid,
    required String fromUid,
    required String type,
  }) async {
    try {
      await NotificationService().create(
        toUid: toUid,
        fromUid: fromUid,
        type: type,
        source: NotifSource.page,
        sourceId: pageId,
        sourceName: pageName,
      );
    } catch (_) {}
  }

  Future<void> requestToJoin(String pageId, String uid) async {
    final ref = _pages.doc(pageId);
    String ownerId = '';
    String pageName = '';
    var sent = false;
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || data?['privacy'] != 'private')
        throw Exception('เพจนี้ไม่ได้เปิดเป็นส่วนตัว');
      final members = List<String>.from(data?['memberIds'] ?? const []);
      if (members.contains(uid)) return;
      final pending = List<String>.from(data?['pendingRequests'] ?? const []);
      if (pending.contains(uid)) return;
      ownerId = data?['ownerId'] as String? ?? '';
      pageName = data?['name'] as String? ?? 'เพจ';
      sent = true;
      transaction.update(ref, {
        'pendingRequests': FieldValue.arrayUnion([uid]),
      });
    });
    if (sent) {
      await _notify(
        pageId: pageId,
        pageName: pageName,
        toUid: ownerId,
        fromUid: uid,
        type: NotifType.pageJoinRequest,
      );
    }
  }

  /// ผู้ขอเข้าร่วมยกเลิกคำขอของตัวเอง
  Future<void> cancelRequest(String pageId, String uid) =>
      _pages.doc(pageId).update({
        'pendingRequests': FieldValue.arrayRemove([uid]),
      });

  Future<void> approveRequest(String pageId, String ownerId, String uid) async {
    final ref = _pages.doc(pageId);
    var pageName = '';
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || data?['ownerId'] != ownerId)
        throw Exception('เฉพาะเจ้าของเพจเท่านั้นที่อนุมัติสมาชิกได้');
      final pending = List<String>.from(data?['pendingRequests'] ?? const []);
      if (!pending.contains(uid)) throw Exception('ไม่พบคำขอเข้าร่วมนี้');
      pageName = data?['name'] as String? ?? 'เพจ';
      transaction.update(ref, {
        'memberIds': FieldValue.arrayUnion([uid]),
        'pendingRequests': FieldValue.arrayRemove([uid]),
      });
    });
    await _notify(
      pageId: pageId,
      pageName: pageName,
      toUid: uid,
      fromUid: ownerId,
      type: NotifType.pageJoinApproved,
    );
  }

  Future<void> declineRequest(String pageId, String ownerId, String uid) async {
    final ref = _pages.doc(pageId);
    var pageName = '';
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || data?['ownerId'] != ownerId)
        throw Exception('เฉพาะเจ้าของเพจเท่านั้นที่ปฏิเสธคำขอได้');
      pageName = data?['name'] as String? ?? 'เพจ';
      transaction.update(ref, {
        'pendingRequests': FieldValue.arrayRemove([uid]),
      });
    });
    await _notify(
      pageId: pageId,
      pageName: pageName,
      toUid: uid,
      fromUid: ownerId,
      type: NotifType.pageJoinDeclined,
    );
  }
}
