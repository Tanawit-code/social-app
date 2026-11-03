import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/storage_service.dart';
import '../utils/image_data.dart';

/// Shared owner-only visual customization dialog for communities and pages.
Future<Map<String, String>?> showBrandCustomizer(
  BuildContext context, {
  required String uid,
  String currentImage = '',
  String currentColor = '#6750A4',
  String imageLabel = 'ภาพปก',
}) async {
  final colors = <String>[
    '#6750A4', '#1565C0', '#00897B', '#2E7D32',
    '#EF6C00', '#C62828', '#AD1457', '#263238',
    '#5D4037', '#37474F',
  ];
  Uint8List? bytes;
  var color = currentColor;
  var removeImage = false;
  return showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('ตกแต่งหน้าชุมชน / เพจ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(imageLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                height: 110,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _brandColor(color),
                  borderRadius: BorderRadius.circular(12),
                  image: bytes == null && currentImage.isNotEmpty && !removeImage
                      ? DecorationImage(
                          image: imageProviderFor(currentImage)!,
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: bytes == null
                    ? null
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(bytes!, fit: BoxFit.cover),
                      ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final file = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1024,
                        maxHeight: 600,
                        imageQuality: 55,
                      );
                      if (file == null) return;
                      final selected = await file.readAsBytes();
                      setLocal(() { bytes = selected; removeImage = false; });
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('เลือกรูป'),
                  ),
                  if (currentImage.isNotEmpty || bytes != null)
                    TextButton.icon(
                      onPressed: () => setLocal(() {
                        bytes = null;
                        removeImage = true;
                      }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('ลบรูป'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('สีธีม', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: colors.map((value) => InkWell(
                  onTap: () => setLocal(() => color = value),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _brandColor(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color == value ? Colors.black : Colors.white,
                        width: color == value ? 3 : 1,
                      ),
                    ),
                    child: color == value
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                )).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                var image = currentImage;
                if (bytes != null) {
                  image = await StorageService().uploadCoverImageBytes(
                    bytes: bytes!,
                    uid: uid,
                  );
                } else if (removeImage) {
                  image = '';
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, {
                    'coverUrl': image,
                    'themeColor': color,
                  });
                }
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('เลือกรูปไม่สำเร็จ: $e')),
                  );
                }
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
}

Color _brandColor(String value) {
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex, radix: 16) ?? 0x6750A4;
  return Color(0xFF000000 | parsed);
}
