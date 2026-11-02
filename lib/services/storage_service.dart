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
  static const _maxCoverBytes = 300 * 1024;

  /// จำนวนรูปสูงสุดต่อ 1 โพสต์ (โพสต์ฟีด / เพจ / ชุมชน)
  /// รูปทั้งหมดอยู่ในเอกสาร Firestore เดียวกัน (จำกัด 1 MiB) จึงจำกัดขนาดรวมด้วย
  /// base64 ใหญ่ขึ้นราว 33% → 640 KB กลายเป็นราว 850 KB เหลือที่ให้ข้อความและฟิลด์อื่น
  static const maxPostImages = 4;
  static const _maxPostTotalBytes = 640 * 1024;

  Future<String> uploadPostImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async => _encode(bytes, _maxPostBytes, 'รูปโพสต์');

  /// คืนข้อความผิดพลาด (ภาษาไทย) ถ้ารูปชุดนี้ใส่ในโพสต์เดียวไม่ได้ ไม่งั้นคืน null
  static String? validatePostImages(List<Uint8List> images) {
    if (images.length > maxPostImages) {
      return 'เลือกรูปได้ไม่เกิน $maxPostImages รูปต่อโพสต์';
    }
    var total = 0;
    for (var i = 0; i < images.length; i++) {
      final size = images[i].length;
      if (size > _maxPostBytes) {
        return 'รูปที่ ${i + 1} ใหญ่เกินไป (${size ~/ 1024} KB, ไม่เกิน '
            '${_maxPostBytes ~/ 1024} KB) กรุณาเลือกรูปอื่นที่เล็กกว่านี้';
      }
      total += size;
    }
    if (total > _maxPostTotalBytes) {
      return 'รูปรวมกันใหญ่เกินไป (${total ~/ 1024} KB, ไม่เกิน '
          '${_maxPostTotalBytes ~/ 1024} KB) กรุณาลดจำนวนรูปหรือเลือกรูปที่เล็กลง';
    }
    return null;
  }

  /// แปลงหลายรูปเป็น data URL เรียงตามลำดับที่เลือก (รูปแรก = รูปหน้าปกของโพสต์)
  Future<List<String>> uploadPostImagesBytes({
    required List<Uint8List> images,
    required String uid,
  }) async {
    final error = validatePostImages(images);
    if (error != null) throw Exception(error);
    return [
      for (final bytes in images) _encode(bytes, _maxPostBytes, 'รูปโพสต์'),
    ];
  }

  /// แชท: 1 ข้อความมีได้หลายรูป (อยู่ในเอกสาร Firestore เดียว จำกัด 1 MiB)
  /// ถ้าเลือกมากกว่านี้ [splitChatImages] จะแบ่งเป็นหลายข้อความให้อัตโนมัติ
  static const maxChatImagesPerMessage = 6;
  static const _maxChatTotalBytes = 640 * 1024;

  /// คืนข้อความผิดพลาด (ภาษาไทย) ถ้ามีรูปใดใหญ่เกินกว่าจะส่งในแชทได้ ไม่งั้นคืน null
  static String? validateChatImages(List<Uint8List> images) {
    for (var i = 0; i < images.length; i++) {
      final size = images[i].length;
      if (size > _maxChatBytes) {
        return 'รูปที่ ${i + 1} ใหญ่เกินไป (${size ~/ 1024} KB, ไม่เกิน '
            '${_maxChatBytes ~/ 1024} KB) กรุณาเลือกรูปอื่นที่เล็กกว่านี้';
      }
    }
    return null;
  }

  /// แบ่งรูปเป็นชุดๆ ชุดละไม่เกิน [maxChatImagesPerMessage] รูป และขนาดรวมไม่เกินที่เอกสารรับได้
  /// (1 ชุด = 1 ข้อความ) คงลำดับที่เลือกไว้
  static List<List<Uint8List>> splitChatImages(List<Uint8List> images) {
    final batches = <List<Uint8List>>[];
    var current = <Uint8List>[];
    var total = 0;
    for (final image in images) {
      final full =
          current.length >= maxChatImagesPerMessage ||
          (current.isNotEmpty && total + image.length > _maxChatTotalBytes);
      if (full) {
        batches.add(current);
        current = <Uint8List>[];
        total = 0;
      }
      current.add(image);
      total += image.length;
    }
    if (current.isNotEmpty) batches.add(current);
    return batches;
  }

  Future<List<String>> uploadChatImagesBytes({
    required List<Uint8List> images,
    required String uid,
  }) async {
    final error = validateChatImages(images);
    if (error != null) throw Exception(error);
    return [
      for (final bytes in images) _encode(bytes, _maxChatBytes, 'รูปแชท'),
    ];
  }

  Future<String> uploadChatImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async => _encode(bytes, _maxChatBytes, 'รูปแชท');

  Future<String> uploadProfileImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async => _encode(bytes, _maxAvatarBytes, 'รูปโปรไฟล์');

  Future<String> uploadCoverImageBytes({
    required Uint8List bytes,
    required String uid,
  }) async => _encode(bytes, _maxCoverBytes, 'รูปปก');

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
