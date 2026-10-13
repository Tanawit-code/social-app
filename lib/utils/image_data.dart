import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// เก็บรูปเป็นสตริง data URL ('data:image/jpeg;base64,...') ลงใน Firestore ได้เลย
/// จึงไม่ต้องใช้ Firebase Storage (ไม่ต้องผูกบัตร / ไม่ต้องอัปเกรด Blaze)
/// ฟิลด์เดิม (mediaUrl / photoUrl / imageUrl) ยังใช้ชื่อเดิม และรองรับ URL ปกติด้วย

String bytesToDataUrl(Uint8List bytes) {
  final isPng =
      bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E;
  final mime = isPng ? 'image/png' : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

// แคชผลถอดรหัส เพื่อไม่ต้อง decode ซ้ำทุกครั้งที่ rebuild (และให้ ImageCache จำรูปได้)
final Map<String, Uint8List> _decoded = {};

Uint8List? _decode(String src) {
  final cached = _decoded[src];
  if (cached != null) return cached;
  try {
    final bytes = base64Decode(src.substring(src.indexOf(',') + 1));
    if (_decoded.length > 80) _decoded.clear();
    _decoded[src] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}

/// data URL -> MemoryImage, URL ปกติ -> NetworkImage, ว่าง/พัง -> null
ImageProvider? imageProviderFor(String? src) {
  if (src == null || src.isEmpty) return null;
  if (src.startsWith('data:')) {
    final bytes = _decode(src);
    return bytes == null ? null : MemoryImage(bytes);
  }
  return NetworkImage(src);
}

/// แสดงรูปจาก data URL หรือ URL ปกติ
class AppImage extends StatelessWidget {
  final String src;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double errorHeight;

  const AppImage({
    required this.src,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorHeight = 150,
    super.key,
  });

  Widget _error() => Container(
    width: width,
    height: height ?? errorHeight,
    color: const Color(0xFFE4E6EB),
    child: const Center(child: Text('โหลดรูปไม่สำเร็จ')),
  );

  @override
  Widget build(BuildContext context) {
    final provider = imageProviderFor(src);
    if (provider == null) return _error();
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => _error(),
    );
  }
}
