import 'profile_link.dart';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/story_model.dart';
import '../services/auth_service.dart';
import '../services/story_service.dart';
import '../services/storage_service.dart';
import '../utils/image_data.dart';
import 'user_avatar.dart';

class StoryStrip extends StatefulWidget {
  final bool createOnly;
  const StoryStrip({this.createOnly = false, super.key});
  @override
  State<StoryStrip> createState() => _StoryStripState();
}

class _StoryStripState extends State<StoryStrip> {
  final _uid = AuthService().currentUser?.uid ?? '';
  final _service = StoryService();

  Future<void> _create() async {
    // เนื้อหาของ sheet แยกเป็น widget ของตัวเอง (มี State/Controller ของตัวเอง)
    // เพื่อไม่ให้ dispose controller ทันทีหลัง pop ตอนที่ TextField ยังอยู่ใน animation ปิด
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateStorySheet(uid: _uid, service: _service),
    );
  }

  void _view(List<Story> stories, int start) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StoryViewer(stories: stories, initialIndex: start),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.createOnly) {
      return TextButton.icon(
        onPressed: _create,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('\u0e2a\u0e23\u0e49\u0e32\u0e07 Story'),
      );
    }
    return SizedBox(
      height: 112,
      child: StreamBuilder<List<Story>>(
        stream: _service.feed(_uid),
        builder: (context, snap) {
          final stories = snap.data ?? const <Story>[];
          final groups = <String, List<Story>>{};
          for (final story in stories) {
            groups.putIfAbsent(story.authorId, () => []).add(story);
          }
          final authors = groups.keys.toList();
          return ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _StoryCircle(
                uid: _uid,
                label: 'เพิ่ม Story',
                hasStory: false,
                onTap: _create,
              ),
              for (var i = 0; i < authors.length; i++)
                _StoryCircle(
                  uid: authors[i],
                  label: '',
                  hasStory: true,
                  onTap: () => _view(
                    stories,
                    stories.indexWhere((story) => story.authorId == authors[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CreateStorySheet extends StatefulWidget {
  final String uid;
  final StoryService service;
  const _CreateStorySheet({required this.uid, required this.service});
  @override
  State<_CreateStorySheet> createState() => _CreateStorySheetState();
}

class _CreateStorySheetState extends State<_CreateStorySheet> {
  final _text = TextEditingController();
  Uint8List? _image;
  String _audience = 'public';
  String _backgroundColor = '#342653';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 640,
      maxHeight: 960,
      imageQuality: 55,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() => _image = bytes);
  }

  Future<void> _submit() async {
    if (_text.text.trim().isEmpty && _image == null) return;
    setState(() => _busy = true);
    try {
      final media = _image == null
          ? null
          : await StorageService().uploadPostImageBytes(
              bytes: _image!,
              uid: widget.uid,
            );
      await widget.service.create(
        authorId: widget.uid,
        text: _text.text,
        mediaUrl: media,
        audience: _audience,
        backgroundColor: _backgroundColor,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('สร้าง Story ไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'สร้าง Story (แสดง 24 ชั่วโมง)',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'เขียนข้อความใน Story',
              border: OutlineInputBorder(),
            ),
          ),
          if (_image != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Image.memory(_image!, height: 180, fit: BoxFit.cover),
            ),
          const SizedBox(height: 10),
          const Text(
            'สีพื้นหลัง Story',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children:
                [
                      '#342653',
                      '#1565C0',
                      '#00897B',
                      '#C62828',
                      '#EF6C00',
                      '#AD1457',
                      '#263238',
                    ]
                    .map(
                      (value) => InkWell(
                        onTap: _busy
                            ? null
                            : () => setState(() => _backgroundColor = value),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _storyColor(value),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _backgroundColor == value
                                  ? Colors.white
                                  : Colors.grey,
                              width: _backgroundColor == value ? 3 : 1,
                            ),
                          ),
                          child: _backgroundColor == value
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.image_outlined),
                label: const Text('เลือกรูป'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _audience,
                  decoration: const InputDecoration(labelText: 'ผู้ชม'),
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('สาธารณะ')),
                    DropdownMenuItem(value: 'friends', child: Text('เพื่อน')),
                    DropdownMenuItem(value: 'private', child: Text('ส่วนตัว')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v != null) setState(() => _audience = v);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('แชร์ Story'),
          ),
        ],
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  final String uid, label;
  final bool hasStory;
  final VoidCallback onTap;
  const _StoryCircle({
    required this.uid,
    required this.label,
    required this.hasStory,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 78,
    child: InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hasStory
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                    width: hasStory ? 3 : 1,
                  ),
                ),
                child: UserAvatar(uid: uid, radius: 27),
              ),
              if (!hasStory)
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 11,
                    child: Icon(Icons.add, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          if (label.isNotEmpty)
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            )
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snap) => Text(
                snap.data?.data()?['name'] as String? ?? 'Story',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
        ],
      ),
    ),
  );
}

class _StoryViewer extends StatefulWidget {
  final List<Story> stories;
  final int initialIndex;
  const _StoryViewer({required this.stories, required this.initialIndex});
  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: PageView.builder(
      controller: _controller,
      itemCount: widget.stories.length,
      itemBuilder: (context, index) {
        final story = widget.stories[index];
        return Stack(
          fit: StackFit.expand,
          children: [
            if (story.mediaUrl != null)
              Image(
                image:
                    imageProviderFor(story.mediaUrl!) ?? const AssetImage(''),
                fit: BoxFit.contain,
              )
            else
              ColoredBox(color: _storyColor(story.backgroundColor)),
            if (story.text.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    story.text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 12)],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: Row(
                children: [
                  UserAvatar(uid: story.authorId, radius: 18, tappable: true),
                  const SizedBox(width: 8),
                  ProfileLink(
                    uid: story.authorId,
                    child: _StoryAuthor(uid: story.authorId),
                  ),
                ],
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                color: Colors.white,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _StoryAuthor extends StatelessWidget {
  final String uid;
  const _StoryAuthor({required this.uid});
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (context, snap) => Text(
      snap.data?.data()?['name'] as String? ?? '',
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    ),
  );
}

Color _storyColor(String value) {
  final parsed =
      int.tryParse(value.replaceFirst('#', ''), radix: 16) ?? 0x342653;
  return Color(0xFF000000 | parsed);
}
