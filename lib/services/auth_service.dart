import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Create: สมัครสมาชิก + สร้างเอกสารผู้ใช้ใน Firestore
  /// ถ้าสร้างบัญชี auth สำเร็จแต่เขียน Firestore ไม่สำเร็จ จะลบบัญชี auth
  /// ที่สร้างไปทิ้ง (rollback) เพื่อไม่ให้ค้างเป็นบัญชีที่ไม่มีข้อมูลโปรไฟล์
  Future<String?> register({
    required String name,
    required String email,
    required String password,
  }) async {
    UserCredential? cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return _mapNetworkError(e);
    }

    try {
      await _db.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': email,
        'bio': '',
        'photoUrl': '',
        'followers': [],
        'following': [],
        'isPrivate': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null; // สำเร็จ ไม่มี error
    } catch (e) {
      try {
        await cred.user!.delete();
      } catch (_) {
        // ignore: ถ้าลบไม่สำเร็จก็ไม่ต้องทำอะไรเพิ่ม แจ้ง error เดิมพอ
      }
      return 'สมัครสมาชิกไม่สำเร็จ: บันทึกข้อมูลโปรไฟล์ไม่ได้ (${_mapNetworkError(e)})';
    }
  }

  /// Read (implicit): ล็อกอิน — ถ้าอีเมลยังไม่เคยลงทะเบียน Firebase จะตอบ
  /// error กลับมาเป็น user-not-found หรือ invalid-credential เสมอ
  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return _mapNetworkError(e);
    }
  }

  /// Update: แก้ไขโปรไฟล์ผู้ใช้
  Future<String?> updateProfile({
    required String uid,
    String? name,
    String? bio,
    String? photoUrl,
    String? coverUrl, // null = ไม่เปลี่ยน, '' = ลบรูปปก
    bool? isPrivate,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name;
      if (bio != null) data['bio'] = bio;
      if (photoUrl != null) data['photoUrl'] = photoUrl;
      if (coverUrl != null) data['coverUrl'] = coverUrl;
      if (isPrivate != null) data['isPrivate'] = isPrivate;
      if (data.isEmpty) return null;

      await _db.collection('users').doc(uid).update(data);
      return null;
    } catch (e) {
      return 'แก้ไขโปรไฟล์ไม่สำเร็จ: ${_mapNetworkError(e)}';
    }
  }

  /// Delete: ลบบัญชีผู้ใช้แบบ cascade —
  /// 1) ลบโพสต์ทั้งหมดที่ authorId == uid (รวม subcollection comments/reactions ของโพสต์นั้น)
  /// 2) ลบเอกสารผู้ใช้ใน Firestore
  /// 3) ลบบัญชี Firebase Auth
  /// ทำแบบนี้เพราะ Firestore ไม่มี cascade delete ให้อัตโนมัติแบบ SQL
  Future<String?> deleteAccount(String uid) async {
    try {
      await _deleteAllPostsByAuthor(uid);
      await _db.collection('users').doc(uid).delete();
      await _auth.currentUser?.delete();
      return null;
    } catch (e) {
      return 'ลบบัญชีไม่สำเร็จ: ${_mapNetworkError(e)}';
    }
  }

  Future<void> _deleteAllPostsByAuthor(String uid) async {
    final posts = await _db
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .get();

    for (final postDoc in posts.docs) {
      await _deletePostWithSubcollections(postDoc.id);
    }
  }

  /// ลบโพสต์ 1 โพสต์ พร้อม subcollection ของมัน (comments, reactions)
  /// เพราะการลบ document หลักใน Firestore ไม่ลบ subcollection ให้อัตโนมัติ
  Future<void> _deletePostWithSubcollections(String postId) async {
    final postRef = _db.collection('posts').doc(postId);

    final comments = await postRef.collection('comments').get();
    final reactions = await postRef.collection('reactions').get();

    // ใช้ batch เพื่อให้ลบพร้อมกันเป็นชุดเดียว (atomic ต่อ batch)
    final batch = _db.batch();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    for (final r in reactions.docs) {
      batch.delete(r.reference);
    }
    batch.delete(postRef);
    await batch.commit();
  }

  Future<void> logout() => _auth.signOut();

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'อีเมลนี้ถูกใช้สมัครไปแล้ว';
      case 'invalid-email':
        return 'รูปแบบอีเมลไม่ถูกต้อง';
      case 'weak-password':
        return 'รหัสผ่านสั้นเกินไป (อย่างน้อย 6 ตัวอักษร)';
      case 'user-not-found':
        return 'ยังไม่มีบัญชีนี้ในระบบ กรุณาสมัครสมาชิกก่อน';
      case 'wrong-password':
      case 'invalid-credential':
        return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      case 'too-many-requests':
        return 'ลองผิดหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่';
      case 'network-request-failed':
        return 'เชื่อมต่อเครือข่ายไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ต';
      default:
        return 'เกิดข้อผิดพลาด: $code';
    }
  }

  String _mapNetworkError(Object e) {
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('network')) {
      return 'เชื่อมต่อเครือข่ายไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ต';
    }
    return msg.replaceFirst('Exception: ', '');
  }
}
