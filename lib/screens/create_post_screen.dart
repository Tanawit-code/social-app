import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/storage_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = TextEditingController();
  final _authService = AuthService();
  final _postService = PostService();
  final _storageService = StorageService();
  final _picker = ImagePicker();

  // ใช้ bytes แทน File เพราะ File ของ dart:io ใช้กับ Flutter Web ไม่ได้
  Uint8List? _selectedImageBytes;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => _selectedImageBytes = bytes);
      }
    } catch (e) {
      setState(() => _errorText = 'เลือกรูปไม่สำเร็จ ลองใหม่อีกครั้ง');
    }
  }

  Future<void> _submit() async {
    final content = _contentController.text.trim();
    final user = _authService.currentUser;

    if (user == null) {
      setState(() => _errorText = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
      return;
    }
    if (content.isEmpty && _selectedImageBytes == null) {
      setState(
        () => _errorText = 'กรุณาใส่ข้อความหรือเลือกรูปอย่างน้อย 1 อย่าง',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      String? mediaUrl;
      String? mediaType;

      if (_selectedImageBytes != null) {
        mediaUrl = await _storageService.uploadPostImageBytes(
          bytes: _selectedImageBytes!,
          uid: user.uid,
        );
        mediaType = 'image';
      }

      await _postService.createPost(
        authorId: user.uid,
        content: content,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() {
        _errorText =
            'โพสต์ไม่สำเร็จ: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สร้างโพสต์'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('โพสต์'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            TextField(
              controller: _contentController,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'คุณกำลังคิดอะไรอยู่?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedImageBytes != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _selectedImageBytes!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                      ),
                      onPressed: () =>
                          setState(() => _selectedImageBytes = null),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: const Text('เพิ่มรูปภาพ'),
            ),
          ],
        ),
      ),
    );
  }
}
