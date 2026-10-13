import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// อัปโหลดวิดีโอไป Cloudinary (แพ็กเกจฟรี ไม่ต้องผูกบัตร)
/// แล้วเก็บเฉพาะ URL ลง Firestore (ฟิลด์ mediaUrl, mediaType = 'video')
/// เหตุผล: เอกสาร Firestore ใหญ่ได้ไม่เกิน 1 MiB จึงเก็บไฟล์วิดีโอตรงๆ ไม่ได้
class VideoUploadService {
  // ★ ใส่ค่าของตัวเองจากหน้า Cloudinary (ดูวิธีในคำอธิบาย)
  static const cloudName = 'oyfgbne4';
  static const uploadPreset = 'social_app';

  static const maxBytes = 30 * 1024 * 1024; // 30 MB
  static const maxSeconds = 60;

  /// คืนค่า URL (https) ของวิดีโอ, throw Exception ถ้าไม่สำเร็จ
  Future<String> uploadVideoBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (cloudName.startsWith('YOUR_') || uploadPreset.startsWith('YOUR_')) {
      throw Exception(
        'ยังไม่ได้ตั้งค่า Cloudinary ใน video_upload_service.dart',
      );
    }
    if (bytes.length > maxBytes) {
      throw Exception(
        'วิดีโอใหญ่เกินไป (${bytes.length ~/ (1024 * 1024)} MB, ไม่เกิน ${maxBytes ~/ (1024 * 1024)} MB)',
      );
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/video/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );

    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final res = await http.Response.fromStream(streamed);
    final data = jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode != 200) {
      final msg =
          (data['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}';
      throw Exception('อัปโหลดวิดีโอไม่สำเร็จ: $msg');
    }
    return data['secure_url'] as String;
  }
}
