import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'push_notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return _mapNetworkError(e);
    }
  }

  Future<String?> sendVerificationEmail() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'กรุณาเข้าสู่ระบบอีกครั้ง';
      await user.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return _mapNetworkError(e);
    }
  }

  Future<void> reloadUser() async => _auth.currentUser?.reload();

  Future<String?> changePassword(String password) async {
    try {
      await _auth.currentUser?.updatePassword(password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return _mapNetworkError(e);
    }
  }

  Future<String?> changeEmail(String email) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 'กรุณาเข้าสู่ระบบอีกครั้ง';
      await user.verifyBeforeUpdateEmail(email.trim());
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('private')
          .doc('account')
          .update({'pendingEmail': email.trim()});
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return _mapNetworkError(e);
    }
  }

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
        'bio': '',
        'photoUrl': '',
        'followers': [],
        'following': [],
        'isPrivate': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _db
          .collection('users')
          .doc(cred.user!.uid)
          .collection('private')
          .doc('account')
          .set({'email': email});
      try {
        await cred.user!.sendEmailVerification();
      } catch (_) {
        // Account settings can resend the verification email after registration.
      }
      return null; // สำเร็จ ไม่มี error
    } catch (e) {
      try {
        await _db
            .collection('users')
            .doc(cred.user!.uid)
            .collection('private')
            .doc('account')
            .delete();
        await _db.collection('users').doc(cred.user!.uid).delete();
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
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user != null) {
        try {
          await _moveEmailToPrivate(user.uid);
        } catch (_) {
          await _auth.signOut();
          rethrow;
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return _mapNetworkError(e);
    }
  }

  Future<void> _moveEmailToPrivate(String uid) async {
    final userRef = _db.collection('users').doc(uid);
    final snap = await userRef.get();
    final oldEmail = snap.data()?['email'] as String?;
    if (oldEmail == null || oldEmail.isEmpty) return;
    final batch = _db.batch();
    batch.set(userRef.collection('private').doc('account'), {
      'email': oldEmail,
    });
    batch.update(userRef, {'email': FieldValue.delete()});
    await batch.commit();
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
  Future<String?> deleteAccount(String uid, {required String password}) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.uid != uid) {
        return 'กรุณาเข้าสู่ระบบบัญชีที่ต้องการลบ';
      }
      final email = user.email;
      if (email == null) return 'บัญชีนี้ไม่รองรับการยืนยันด้วยรหัสผ่าน';
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      await PushNotificationService.instance.stopListening();
      await FirebaseFunctions.instance.httpsCallable('deleteMyAccount').call();
      await _auth.signOut();
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'ลบบัญชีไม่สำเร็จ (${e.code})';
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e.code);
    } catch (e) {
      return 'ลบบัญชีไม่สำเร็จ: ${_mapNetworkError(e)}';
    }
  }
  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await PushNotificationService.instance.unregisterCurrentDevice(uid);
      } catch (_) {}
    }
    await PushNotificationService.instance.stopListening();
    await _auth.signOut();
  }

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
      case 'requires-recent-login':
        return 'เพื่อความปลอดภัย กรุณาออกจากระบบแล้วเข้าสู่ระบบใหม่ก่อนทำรายการนี้';
      case 'operation-not-allowed':
        return 'ฟีเจอร์นี้ยังไม่ได้เปิดใช้ใน Firebase Authentication';
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
