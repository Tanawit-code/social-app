import 'package:cloud_firestore/cloud_firestore.dart';

class PageService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _pages => _db.collection('pages');

  Stream<QuerySnapshot<Map<String, dynamic>>> pages() =>
      _pages.orderBy('createdAt', descending: true).limit(200).snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> page(String pageId) =>
      _pages.doc(pageId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> posts(String pageId) =>
      _db.collection('posts').where('pageId', isEqualTo: pageId).snapshots();

  Future<String> createPage({required String ownerId, required String name, required String description, required String privacy, String? photoUrl}) async {
    if (ownerId.isEmpty || name.trim().isEmpty) throw Exception('กรุณาระบุชื่อเพจและเข้าสู่ระบบ');
    if (privacy != 'public' && privacy != 'private') throw Exception('รูปแบบการมองเห็นเพจไม่ถูกต้อง');
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

  Future<void> updatePagePhoto({required String pageId, required String ownerId, required String photoUrl}) async {
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
      if (!snap.exists || data?['privacy'] != 'public') throw Exception('เพจนี้ไม่ได้เปิดเป็นสาธารณะ');
      transaction.update(ref, {'memberIds': FieldValue.arrayUnion([uid])});
    });
  }

  Future<void> requestToJoin(String pageId, String uid) async {
    final ref = _pages.doc(pageId);
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || data?['privacy'] != 'private') throw Exception('เพจนี้ไม่ได้เปิดเป็นส่วนตัว');
      final members = List<String>.from(data?['memberIds'] ?? const []);
      if (members.contains(uid)) return;
      transaction.update(ref, {'pendingRequests': FieldValue.arrayUnion([uid])});
    });
  }

  Future<void> approveRequest(String pageId, String ownerId, String uid) async {
    final ref = _pages.doc(pageId);
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data();
      if (!snap.exists || data?['ownerId'] != ownerId) throw Exception('เฉพาะเจ้าของเพจเท่านั้นที่อนุมัติสมาชิกได้');
      final pending = List<String>.from(data?['pendingRequests'] ?? const []);
      if (!pending.contains(uid)) throw Exception('ไม่พบคำขอเข้าร่วมนี้');
      transaction.update(ref, {
        'memberIds': FieldValue.arrayUnion([uid]),
        'pendingRequests': FieldValue.arrayRemove([uid]),
      });
    });
  }

}
