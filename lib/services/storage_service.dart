import 'dart:typed_data';
import '../utils/image_data.dart';

/// เก็บรูปแบบฟรี: ไม่ใช้ Firebase Storage แต่แปลงรูปเป็น data URL (base64)
/// แล้วให้ผู้เรียกบันทึกลง Firestore (ฟิลด์ mediaUrl / photoUrl / imageUrl)
/// ชื่อเมธอดและวิธีเรียกเหมือนเดิมทุกอย่าง จึงไม่ต้องแก้ที่เรียกใช้
/// รูปต้องถูกย่อก่อนส่งมา (ที่ image_picker: maxWidth/maxHeight/imageQuality)
/// เพราะเอกสาร Firestore ใหญ่ได้ไม่เกิน 1 MiB
class StorageService {
  static const _maxPostBytes = 250 * 1024;
  static const _maxChatBytes = 200 * 1024;
  static const _maxAvatarBytes = 100 * 1024;

  Future<String> uploadPostImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async => _encode(bytes, _maxPostBytes, 'รูปโพสต์');

  Future<String> uploadChatImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async => _encode(bytes, _maxChatBytes, 'รูปแชท');

  Future<String> uploadProfileImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async => _encode(bytes, _maxAvatarBytes, 'รูปโปรไฟล์');

  /// รูปอยู่ในเอกสารอยู่แล้ว ไม่มีไฟล์ให้ลบ (คงไว้เพื่อไม่ต้องแก้ที่เรียกใช้)
  Future<void> deleteByUrl(String url) async {}

  String _encode(Uint8List bytes, int maxBytes, String label) {
    if (bytes.length > maxBytes) {
      throw Exception(
        '$label ใหญ่เกินไป (${bytes.length ~/ 1024} KB, ไม่เกิน ${maxBytes ~/ 1024} KB) '
        'กรุณาเลือกรูปอื่นที่เล็กกว่านี้',
      );
    }
    return bytesToDataUrl(bytes);
  }
}
