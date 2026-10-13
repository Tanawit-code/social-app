import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// อัปโหลดรูปภาพจาก bytes (ใช้ได้ทั้ง mobile และ Flutter Web)
  /// คืนค่าเป็น download URL, throw Exception ถ้าอัปโหลดไม่สำเร็จ
  Future<String> uploadPostImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async {
    try {
      final fileName =
          'posts/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(fileName);
      final task = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await task.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw Exception('อัปโหลดรูปไม่สำเร็จ: ${e.message}');
    }
  }
}
