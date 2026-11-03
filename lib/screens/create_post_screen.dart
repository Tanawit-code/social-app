import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/storage_service.dart';
import '../services/video_upload_service.dart';
import '../services/mention_service.dart';
import '../widgets/mention_text_field.dart';

class CreatePostScreen extends StatefulWidget {
  final String? pageId;
  const CreatePostScreen({this.pageId, super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentController = MentionController();
  final _authService = AuthService();
  final _postService = PostService();
  final _storageService = StorageService();
  final _videoService = VideoUploadService();
  final _picker = ImagePicker();

  // ใช้ bytes แทน File เพราะ File ของ dart:io ใช้กับ Flutter Web ไม่ได้
  final List<Uint8List> _selectedImages =
      []; // เลือกได้หลายรูป (สูงสุด maxPostImages)
  Uint8List? _selectedVideoBytes;
  String? _selectedVideoName;
  bool _submitting = false;
  bool _shareAsReel = false;
  String _audience = 'public';
  String? _errorText;
  late MentionScope _mentionScope;

  @override
  void initState() {
    super.initState();
    _mentionScope = _scopeFor(_audience);
  }

  /// แท็กได้ใครบ้าง: เพจ = ตามความเป็นสาธารณะ/ส่วนตัวของเพจ, โพสต์ฟีด = ตามผู้ชมที่เลือก
  MentionScope _scopeFor(String audience) {
    final uid = _authService.currentUser?.uid ?? '';
    return widget.pageId != null
        ? MentionScope.page(widget.pageId!, uid)
        : MentionScope.audience(audience, uid);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final remaining = StorageService.maxPostImages - _selectedImages.length;
    if (remaining <= 0) {
      setState(
        () => _errorText =
            'เลือกรูปได้ไม่เกิน ${StorageService.maxPostImages} รูปต่อโพสต์',
      );
      return;
    }
    try {
      // pickMultiImage ต้องมี limit >= 2 จึงใช้ pickImage ตอนเหลือที่ว่างรูปเดียว
      final List<XFile> picked;
      if (remaining == 1) {
        final one = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 55,
          maxWidth: 640,
          maxHeight: 640,
        );
        picked = one == null ? const [] : [one];
      } else {
        picked = await _picker.pickMultiImage(
          imageQuality: 55,
          maxWidth: 640,
          maxHeight: 640,
          limit: remaining,
        );
      }
      if (picked.isEmpty) return;
      // บางแพลตฟอร์ม (เช่น เว็บ) ไม่สนใจ limit จึงตัดส่วนเกินทิ้งเอง
      final added = <Uint8List>[
        for (final file in picked.take(remaining)) await file.readAsBytes(),
      ];
      final next = [..._selectedImages, ...added];
      final error = StorageService.validatePostImages(next);
      if (!mounted) return;
      if (error != null) {
        setState(() => _errorText = error);
        return;
      }
      setState(() {
        _errorText = picked.length > remaining
            ? 'เลือกรูปได้ไม่เกิน ${StorageService.maxPostImages} รูปต่อโพสต์ '
                  '(ใช้ $remaining รูปแรกที่เลือก)'
            : null;
        _selectedImages
          ..clear()
          ..addAll(next);
        _shareAsReel = false;
        _selectedVideoBytes =
            null; // 1 โพสต์ = รูป (หลายรูปได้) หรือวิดีโออย่างใดอย่างหนึ่ง
        _selectedVideoName = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = 'เลือกรูปไม่สำเร็จ ลองใหม่อีกครั้ง');
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: VideoUploadService.maxSeconds),
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > VideoUploadService.maxBytes) {
        setState(
          () => _errorText =
              'วิดีโอใหญ่เกินไป (ไม่เกิน ${VideoUploadService.maxBytes ~/ (1024 * 1024)} MB)',
        );
        return;
      }
      setState(() {
        _errorText = null;
        _selectedVideoBytes = bytes;
        _selectedVideoName = picked.name;
        _selectedImages.clear();
      });
    } catch (e) {
      setState(() => _errorText = 'เลือกวิดีโอไม่สำเร็จ ลองใหม่อีกครั้ง');
    }
  }

  Future<void> _submit() async {
    final content = _contentController.encoded.trim();
    final user = _authService.currentUser;

    if (user == null) {
      setState(() => _errorText = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่');
      return;
    }
    if (content.isEmpty &&
        _selectedImages.isEmpty &&
        _selectedVideoBytes == null) {
      setState(
        () => _errorText = 'กรุณาใส่ข้อความ รูป หรือวิดีโออย่างน้อย 1 อย่าง',
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
      var moreMediaUrls = <String>[];

      if (_selectedImages.isNotEmpty) {
        final urls = await _storageService.uploadPostImagesBytes(
          images: _selectedImages,
          uid: user.uid,
        );
        mediaUrl = urls
            .first; // รูปแรก = mediaUrl เดิม, รูปที่เหลือเก็บใน moreMediaUrls
        moreMediaUrls = urls.sublist(1);
        mediaType = 'image';
      } else if (_selectedVideoBytes != null) {
        mediaUrl = await _videoService.uploadVideoBytes(
          bytes: _selectedVideoBytes!,
          filename: _selectedVideoName ?? 'video.mp4',
        );
        mediaType = 'video';
      }

      await _postService.createPost(
        authorId: user.uid,
        content: content,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        moreMediaUrls: moreMediaUrls,
        pageId: widget.pageId,
        audience: widget.pageId == null ? _audience : 'public',
        isReel: _shareAsReel && mediaType == 'video',
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
        title: Text(widget.pageId == null ? 'สร้างโพสต์' : 'โพสต์ลงเพจ'),
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
            MentionTextField(
              controller: _contentController,
              scope: _mentionScope,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: _mentionScope.enabled
                    ? 'คุณกำลังคิดอะไรอยู่? (พิมพ์ @ เพื่อแท็กเพื่อน)'
                    : 'คุณกำลังคิดอะไรอยู่?',
                helperText: _mentionScope.enabled
                    ? null
                    : 'โพสต์ส่วนตัว/เฉพาะเพื่อนของคนอื่น ไม่สามารถแท็กได้',
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.pageId == null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _audience,
                decoration: const InputDecoration(
                  labelText: 'ใครเห็นโพสต์นี้ได้บ้าง',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people_outline),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'public',
                    child: Text('สาธารณะ — ทุกคนเห็นได้'),
                  ),
                  DropdownMenuItem(
                    value: 'friends',
                    child: Text('เพื่อน — คนที่ตอบรับคำขอแล้ว'),
                  ),
                  DropdownMenuItem(
                    value: 'private',
                    child: Text('ส่วนตัว — เฉพาะฉัน'),
                  ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _audience = value;
                            _mentionScope = _scopeFor(value);
                          });
                        }
                      },
              ),
            ],
            const SizedBox(height: 12),
            if (_selectedImages.isNotEmpty) ...[
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _selectedImages[i],
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          tooltip: 'ลบรูปที่ ${i + 1}',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.white,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                          ),
                          onPressed: _submitting
                              ? null
                              : () =>
                                    setState(() => _selectedImages.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_selectedImages.length}/${StorageService.maxPostImages} รูป',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
            if (_selectedVideoBytes != null)
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.videocam, size: 32),
                  title: Text(
                    _selectedVideoName ?? 'video',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${(_selectedVideoBytes!.length / (1024 * 1024)).toStringAsFixed(1)} MB',
                  ),
                  trailing: IconButton(
                    tooltip: 'ลบวิดีโอที่เลือก',
                    icon: const Icon(Icons.close),
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                            _selectedVideoBytes = null;
                            _selectedVideoName = null;
                          }),
                  ),
                ),
              ),
            if (_selectedVideoBytes != null && widget.pageId == null)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _shareAsReel,
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _shareAsReel = value),
                title: const Text('แชร์เป็น Reel'),
                subtitle: const Text('วิดีโอนี้จะแสดงในฟีด Reels ด้วย'),
              ),
            if (_submitting && _selectedVideoBytes != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'กำลังอัปโหลดวิดีโอ อาจใช้เวลาสักครู่...',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _submitting ||
                            _selectedImages.length >=
                                StorageService.maxPostImages
                        ? null
                        : _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _selectedImages.isEmpty
                          ? 'เพิ่มรูปภาพ'
                          : 'เพิ่มรูปภาพ (${_selectedImages.length}/${StorageService.maxPostImages})',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickVideo,
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('เพิ่มวิดีโอ'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
