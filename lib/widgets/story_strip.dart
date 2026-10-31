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
    final text = TextEditingController();
    Uint8List? image;
    var audience = 'public';
    var busy = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
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
                controller: text,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'เขียนข้อความใน Story',
                  border: OutlineInputBorder(),
                ),
              ),
              if (image != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Image.memory(image!, height: 180, fit: BoxFit.cover),
                ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final file = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              maxWidth: 640,
                              maxHeight: 960,
                              imageQuality: 55,
                            );
                            if (!sheetContext.mounted) return;
                            if (file != null) {
                              final bytes = await file.readAsBytes();
                              if (!sheetContext.mounted) return;
                              setSheetState(() => image = bytes);
                            }
                          },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('เลือกรูป'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: audience,
                      decoration: const InputDecoration(labelText: 'ผู้ชม'),
                      items: const [
                        DropdownMenuItem(
                          value: 'public',
                          child: Text('สาธารณะ'),
                        ),
                        DropdownMenuItem(
                          value: 'friends',
                          child: Text('เพื่อน'),
                        ),
                        DropdownMenuItem(
                          value: 'private',
                          child: Text('ส่วนตัว'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setSheetState(() => audience = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (text.text.trim().isEmpty && image == null) return;
                        setSheetState(() => busy = true);
                        var popped = false;
                        try {
                          final media = image == null
                              ? null
                              : await StorageService().uploadPostImageBytes(
                                  bytes: image!,
                                  uid: _uid,
                                );
                          await _service.create(
                            authorId: _uid,
                            text: text.text,
                            mediaUrl: media,
                            audience: audience,
                          );
                          if (sheetContext.mounted) {
                            popped = true;
                            Navigator.pop(sheetContext);
                          }
                        } catch (e) {
                          if (sheetContext.mounted)
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text('สร้าง Story ไม่สำเร็จ: $e'),
                              ),
                            );
                        } finally {
                          if (!popped && sheetContext.mounted)
                            setSheetState(() => busy = false);
                        }
                      },
                child: busy
                    ? const CircularProgressIndicator()
                    : const Text('แชร์ Story'),
              ),
            ],
          ),
        ),
      ),
    );
    text.dispose();
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
                    color: hasStory ? Colors.deepPurple : Colors.grey.shade400,
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
              const ColoredBox(color: Color(0xFF342653)),
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
                  UserAvatar(uid: story.authorId, radius: 18),
                  const SizedBox(width: 8),
                  _StoryAuthor(uid: story.authorId),
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
