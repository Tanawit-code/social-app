import 'package:flutter/material.dart';
import 'post_media.dart';

/// สื่อในข้อความแชท: รูปเดียว / หลายรูป (ตาราง กดดูเต็มจอและปัดดูทีละรูปได้) / วิดีโอ
class ChatMessageMedia extends StatelessWidget {
  final Map<String, dynamic> data;
  final double width;
  const ChatMessageMedia({required this.data, this.width = 240, super.key});

  static String? _first(Map<String, dynamic> data) {
    final url = data['imageUrl'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// รูปทั้งหมดของข้อความตามลำดับ (ว่าง = ไม่มีรูป)
  static List<String> imagesOf(Map<String, dynamic> data) {
    final first = _first(data);
    if (first == null) return const [];
    final more = data['moreImageUrls'];
    return [
      first,
      if (more is List) ...more.whereType<String>().where((u) => u.isNotEmpty),
    ];
  }

  static String? videoOf(Map<String, dynamic> data) {
    final url = data['videoUrl'];
    return url is String && url.isNotEmpty ? url : null;
  }

  /// ข้อความนี้มีรูปหรือวิดีโอหรือไม่
  static bool hasMedia(Map<String, dynamic> data) =>
      videoOf(data) != null || _first(data) != null;

  @override
  Widget build(BuildContext context) {
    final video = videoOf(data);
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: SizedBox(
        width: width,
        child: video != null
            ? PostMedia(url: video, type: 'video')
            : PostImageGallery(urls: imagesOf(data)),
      ),
    );
  }
}
