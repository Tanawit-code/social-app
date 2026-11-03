import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

class PageService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _pages =>
      _db.collection('pages');

  /// เจ้าของเพจหรือผู้ดูแล (moderatorIds) หรือไม่
  static bool canModerate(Map<String, dynamic>? data, String uid) {
    if (data == null || uid.isEmpty) return false;
    return data['ownerId'] == uid ||
        List<String>.from(data['moderatorIds'] ?? const []).contains(uid);
  }

  static bool isBanned(Map<String, dynamic>? data, String uid) =>
      List<String>.from(data?['bannedIds'] ?? const []).contains(uid);

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
      'moderatorIds': [],
      'bannedIds': [],
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
      if (isBanned(data, uid)) throw Exception('คุณถูกแบนจากเพจนี้');
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
      if (isBanned(data, uid)) throw Exception('คุณถูกแบนจากเพจนี้');
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

  /// เจ้าของเพจหรือผู้ดูแลอนุมัติคำขอ ([byUid] = ผู้กดอนุมัติ)
  Future<void> approveRequest(String pageId, String byUid, String uid) async {
    final ref = _pages.doc(pageId);
    var pageName = '';
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || !canModerate(data, byUid))
        throw Exception('เฉพาะเจ้าของหรือผู้ดูแลเพจเท่านั้นที่อนุมัติสมาชิกได้');
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
      fromUid: byUid,
      type: NotifType.pageJoinApproved,
    );
  }

  Future<void> declineRequest(String pageId, String byUid, String uid) async {
    final ref = _pages.doc(pageId);
    var pageName = '';
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || !canModerate(data, byUid))
        throw Exception('เฉพาะเจ้าของหรือผู้ดูแลเพจเท่านั้นที่ปฏิเสธคำขอได้');
      pageName = data?['name'] as String? ?? 'เพจ';
      transaction.update(ref, {
        'pendingRequests': FieldValue.arrayRemove([uid]),
      });
    });
    await _notify(
      pageId: pageId,
      pageName: pageName,
      toUid: uid,
      fromUid: byUid,
      type: NotifType.pageJoinDeclined,
    );
  }

  /// ตั้ง/ถอดผู้ดูแล — เฉพาะเจ้าของเพจ (rules บังคับ)
  Future<void> setModerator(String pageId, String uid, bool moderator) =>
      _pages.doc(pageId).update({
        'moderatorIds': moderator
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      });

  /// นำสมาชิกออกจากเพจ (เตะ) — ถ้า [ban] = true จะแบนด้วย (เข้าร่วม/ดู/โพสต์ไม่ได้อีก)
  /// [targetIsModerator] ใช้เมื่อเจ้าของนำผู้ดูแลออก เพื่อถอดสิทธิ์ผู้ดูแลพร้อมกัน
  Future<void> removeMember(
    String pageId,
    String uid, {
    bool ban = false,
    bool targetIsModerator = false,
  }) => _pages.doc(pageId).update({
    'memberIds': FieldValue.arrayRemove([uid]),
    'pendingRequests': FieldValue.arrayRemove([uid]),
    if (ban) 'bannedIds': FieldValue.arrayUnion([uid]),
    if (targetIsModerator) 'moderatorIds': FieldValue.arrayRemove([uid]),
  });

  Future<void> unbanMember(String pageId, String uid) =>
      _pages.doc(pageId).update({
        'bannedIds': FieldValue.arrayRemove([uid]),
      });

  /// สมาชิกออกจากเพจด้วยตัวเอง (เจ้าของออกไม่ได้ ต้องลบเพจแทน)
  /// ถอดสิทธิ์ผู้ดูแลของตัวเองพร้อมกันถ้าเป็นผู้ดูแล
  Future<void> leavePage(String pageId, String uid) async {
    final ref = _pages.doc(pageId);
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || data == null) throw Exception('ไม่พบเพจนี้');
      if (data['ownerId'] == uid) {
        throw Exception('เจ้าของเพจออกจากเพจไม่ได้ ต้องลบเพจแทน');
      }
      final members = List<String>.from(data['memberIds'] ?? const []);
      if (!members.contains(uid)) return;
      final mods = List<String>.from(data['moderatorIds'] ?? const []);
      transaction.update(ref, {
        'memberIds': FieldValue.arrayRemove([uid]),
        if (mods.contains(uid)) 'moderatorIds': FieldValue.arrayRemove([uid]),
      });
    });
  }

  /// ลบเพจถาวร (เฉพาะเจ้าของ) — ลบโพสต์ทั้งหมดของเพจก่อน แล้วค่อยลบตัวเพจ
  /// ถ้าขั้นตอนใดล้มเหลวเพจยังอยู่ และกดลบซ้ำได้
  Future<void> deletePage(String pageId, String ownerId) async {
    final ref = _pages.doc(pageId);
    final snap = await ref.get();
    if (!snap.exists) return;
    if (snap.data()?['ownerId'] != ownerId) {
      throw Exception('เฉพาะเจ้าของเพจเท่านั้นที่ลบเพจได้');
    }
    final posts = await _db
        .collection('posts')
        .where('pageId', isEqualTo: pageId)
        .get();
    await _deleteInChunks(posts.docs.map((d) => d.reference).toList());
    await ref.delete();
  }

  Future<void> _deleteInChunks(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }
}
