import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'storage_service.dart';
import 'video_upload_service.dart';

/// เลือก/เตรียมรูปและวิดีโอสำหรับแชท (ใช้ร่วมกันทั้งแชท 1:1 และแชทกลุ่ม)
/// ทุกเมธอด throw Exception ที่มีข้อความภาษาไทยเมื่อส่งไม่ได้
class ChatMediaService {
  static const maxPickImages = 20;
  final _picker = ImagePicker();

  /// เลือกหลายรูปจากคลัง แล้วแปลงเป็น data URL แบ่งเป็นชุด ชุดละ 1 ข้อความ
  /// คืน null ถ้าผู้ใช้ยกเลิก
  Future<List<List<String>>?> pickImageBatches(String uid) async {
    final picked = await _picker.pickMultiImage(
      imageQuality: 55,
      maxWidth: 640,
      maxHeight: 640,
      limit: maxPickImages,
    );
    if (picked.isEmpty) return null;
    // บางแพลตฟอร์ม (เช่น เว็บ) ไม่สนใจ limit จึงตัดส่วนเกินทิ้งเอง
    final images = <Uint8List>[
      for (final file in picked.take(maxPickImages)) await file.readAsBytes(),
    ];
    final error = StorageService.validateChatImages(images);
    if (error != null) throw Exception(error);
    final storage = StorageService();
    final batches = <List<String>>[];
    for (final chunk in StorageService.splitChatImages(images)) {
      batches.add(await storage.uploadChatImagesBytes(images: chunk, uid: uid));
    }
    return batches;
  }

  /// เลือกวิดีโอ 1 ไฟล์ อัปโหลดไป Cloudinary แล้วคืน URL (null ถ้าผู้ใช้ยกเลิก)
  Future<String?> pickAndUploadVideo() async {
    final picked = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: VideoUploadService.maxSeconds),
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return VideoUploadService().uploadVideoBytes(
      bytes: bytes,
      filename: picked.name,
    );
  }
}
