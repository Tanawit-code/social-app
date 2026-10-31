import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import 'create_post_screen.dart';
import 'profile_screen.dart';
import '../widgets/user_avatar.dart';
import '../widgets/post_media.dart';
import 'pages_screen.dart';
import '../widgets/suggested_people.dart';
import '../widgets/story_strip.dart';
import 'reels_screen.dart';
import 'communities_screen.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final _postService = PostService();
  final _authService = AuthService();

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final uid = _authService.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text(
          'Social',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        // ค้นหา/แชท/แจ้งเตือน/โปรไฟล์ ย้ายไปอยู่ bottom bar (MainShell) แล้ว
        actions: [
          IconButton(
            tooltip: 'ชุมชน',
            icon: const Icon(Icons.groups_2_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunitiesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'เพจ',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PagesScreen()),
            ),
          ),
          IconButton(
            tooltip: 'ออกจากระบบ',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: StreamBuilder<List<Post>>(
        stream: _postService.feedStream(viewerId: uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(message: 'โหลดฟีดไม่สำเร็จ: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(10),
            children: [
              _ComposerBar(uid: uid),
              const SizedBox(height: 10),
              const StoryStrip(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReelsScreen()),
                  ),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('ดู Reels'),
                ),
              ),
              SuggestedPeople(uid: uid),
              const SizedBox(height: 10),
              if (posts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('ยังไม่มีโพสต์ ลองเป็นคนแรกที่โพสต์สิ!'),
                  ),
                )
              else
                ...posts.map(
                  (p) => Padding(
                    key: ValueKey(p.id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: PostCard(
                      post: p,
                      currentUid: uid,
                      postService: _postService,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreatePostScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// ช่อง "คุณกำลังคิดอะไรอยู่?" ด้านบนฟีด แบบ Facebook
class _ComposerBar extends StatelessWidget {
  final String uid;
  const _ComposerBar({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                UserAvatar(uid: uid),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreatePostScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'คุณกำลังคิดอะไรอยู่?',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _quickAction(
                  context,
                  Icons.photo_library,
                  'รูปภาพ',
                  Colors.green,
                ),
                const StoryStrip(createOnly: true),
                _quickAction(context, Icons.videocam, 'วิดีโอ', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return TextButton.icon(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreatePostScreen()),
      ),
      icon: Icon(icon, color: color, size: 20),
      label: Text(
        label,
        style: const TextStyle(color: Colors.black54, fontSize: 13),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// แปลง Timestamp เป็นข้อความเวลาแบบ relative (เมื่อสักครู่ / 5 นาทีที่แล้ว ...)
String formatRelativeTime(Timestamp? ts) {
  if (ts == null) return '';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inSeconds < 60) return 'เมื่อสักครู่';
  if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
  if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
  if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
  final d = ts.toDate();
  return '${d.day}/${d.month}/${d.year}';
}

/// ดึงชื่อผู้ใช้จาก collection users ตาม authorId (uid) มาแสดง
/// cache ผลไว้ในตัวแปร static ระดับไฟล์ กันยิง Firestore ซ้ำตอน rebuild
class AuthorName extends StatefulWidget {
  final String uid;
  final TextStyle? style;
  const AuthorName({required this.uid, this.style, super.key});

  @override
  State<AuthorName> createState() => _AuthorNameState();
}

class _AuthorNameState extends State<AuthorName> {
  static final Map<String, String> _cache = {};
  String? _name;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_cache.containsKey(widget.uid)) {
      setState(() => _name = _cache[widget.uid]);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final name = doc.data()?['name'] as String?;
      final resolved = (name != null && name.trim().isNotEmpty)
          ? name
          : 'ผู้ใช้ไม่ทราบชื่อ';
      _cache[widget.uid] = resolved;
      if (mounted) setState(() => _name = resolved);
    } catch (_) {
      if (mounted) setState(() => _name = 'ผู้ใช้ไม่ทราบชื่อ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _name ?? 'กำลังโหลด...',
      overflow: TextOverflow.ellipsis,
      style: widget.style ?? const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}

class _ReactionOption {
  final String type;
  final String emoji;
  final String label;
  const _ReactionOption(this.type, this.emoji, this.label);
}

const _reactionOptions = [
  _ReactionOption('like', '\u{1F44D}', 'Like'),
  _ReactionOption('love', '\u2764\uFE0F', 'Love'),
  _ReactionOption('care', '\u{1F917}', 'Care'),
  _ReactionOption('haha', '\u{1F602}', 'Haha'),
  _ReactionOption('wow', '\u{1F62E}', 'Wow'),
  _ReactionOption('sad', '\u{1F622}', 'Sad'),
  _ReactionOption('angry', '\u{1F621}', 'Angry'),
];

class PostCard extends StatefulWidget {
  final Post post;
  final String currentUid;
  final PostService postService;

  const PostCard({
    required this.post,
    required this.currentUid,
    required this.postService,
    super.key,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _deleting = false;

  Post get post => widget.post;
  String get currentUid => widget.currentUid;
  PostService get postService => widget.postService;

  bool get _isOwner => post.authorId == currentUid;

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _myReactionStream =>
      FirebaseFirestore.instance
          .collection('posts')
          .doc(post.id)
          .collection('reactions')
          .doc(currentUid)
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _reactionsStream =>
      postService.reactionsStream(post.id);

  Future<void> _react(String type) async {
    try {
      await postService.setReaction(
        postId: post.id,
        uid: currentUid,
        type: type,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ทำรายการไม่สำเร็จ: $e')));
    }
  }

  void _openReactionPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 8,
            runSpacing: 8,
            children: _reactionOptions
                .map(
                  (option) => InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _react(option.type);
                    },
                    child: SizedBox(
                      width: 58,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            option.emoji,
                            style: const TextStyle(fontSize: 32),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            option.label,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _sharePost() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (post.sharedPostId == null)
              ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('แชร์ลงฟีด'),
                onTap: () => Navigator.pop(sheetContext, 'feed'),
              ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('แชร์ผ่านแอปอื่น'),
              onTap: () => Navigator.pop(sheetContext, 'external'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'feed') {
      final options = await showDialog<_ReshareOptions>(
        context: context,
        builder: (_) => const _ReshareDialog(),
      );
      if (options == null) return;
      try {
        await postService.sharePost(
          authorId: currentUid,
          original: post,
          caption: options.caption,
          audience: options.audience,
        );
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('แชร์โพสต์ลงฟีดแล้ว')));
      } catch (error) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('แชร์โพสต์ไม่สำเร็จ: $error')));
      }
      return;
    }
    if (choice != 'external') return;
    final parts = <String>[
      if (post.content.trim().isNotEmpty) post.content.trim(),
      if (post.mediaUrl != null && post.mediaUrl!.trim().isNotEmpty)
        post.mediaUrl!.trim(),
      'โพสต์นี้แชร์จาก Social (รหัสโพสต์: ${post.id})',
    ];
    try {
      await SharePlus.instance.share(
        ShareParams(text: parts.join('\n\n'), title: 'แชร์โพสต์'),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('แชร์โพสต์ไม่สำเร็จ: $e')));
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(uid: post.authorId)),
    );
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CommentsSheet(
        postId: post.id,
        postOwnerId: post.authorId,
        currentUid: currentUid,
        postService: postService,
      ),
    );
  }

  void _report() {
    showDialog(
      context: context,
      builder: (_) => _ReportDialog(
        postId: post.id,
        currentUid: currentUid,
        postService: postService,
      ),
    );
  }

  Future<void> _hideFromFeed() async {
    try {
      await postService.hidePost(currentUid, post.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('ซ่อนโพสต์นี้จากฟีดแล้ว'),
          action: SnackBarAction(
            label: 'เลิกทำ',
            onPressed: () => postService.unhidePost(currentUid, post.id),
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ซ่อนโพสต์ไม่สำเร็จ: $error')));
    }
  }

  Future<void> _muteAuthor() async {
    try {
      await postService.muteAuthor(currentUid, post.authorId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('ซ่อนโพสต์จากบัญชีนี้แล้ว'),
          action: SnackBarAction(
            label: 'เลิกทำ',
            onPressed: () =>
                postService.unmuteAuthor(currentUid, post.authorId),
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ซ่อนบัญชีไม่สำเร็จ: $error')));
    }
  }

  Future<void> _editPost() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EditPostDialog(post: post, postService: postService),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('บันทึกการแก้ไขโพสต์แล้ว')));
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบโพสต์นี้?'),
        content: const Text(
          'ลบแล้วจะไม่สามารถกู้คืนได้ รวมถึงคอมเมนต์และปฏิกิริยาทั้งหมดในโพสต์นี้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await postService.deletePost(post.id);
      // ไม่ต้อง setState ต่อ เพราะ widget นี้จะหายไปจาก feedStream เองอัตโนมัติ
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบโพสต์ไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _deleting ? 0.4 : 1,
      child: IgnorePointer(
        ignoring: _deleting,
        child: Card(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _openProfile,
                      child: UserAvatar(uid: post.authorId),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _openProfile,
                            child: AuthorName(uid: post.authorId),
                          ),
                          Text(
                            formatRelativeTime(post.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_deleting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isOwner)
                            IconButton(
                              tooltip: 'แก้ไขโพสต์',
                              onPressed: _editPost,
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'report') _report();
                              if (v == 'hide') _hideFromFeed();
                              if (v == 'mute') _muteAuthor();
                              if (v == 'delete') _confirmDelete();
                            },
                            itemBuilder: (_) => [
                              if (_isOwner)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'ลบโพสต์',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                )
                              else ...[
                                const PopupMenuItem(
                                  value: 'hide',
                                  child: Text('ซ่อนโพสต์นี้'),
                                ),
                                const PopupMenuItem(
                                  value: 'mute',
                                  child: Text('ซ่อนโพสต์จากบัญชีนี้'),
                                ),
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Text('รายงานโพสต์'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (post.sharedPostId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.repeat,
                          size: 15,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'แชร์โพสต์จาก ',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        if (post.sharedAuthorId != null)
                          AuthorName(
                            uid: post.sharedAuthorId!,
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                if (post.content.isNotEmpty)
                  Text(post.content, style: const TextStyle(fontSize: 15)),
                if (post.sharedPostId != null) _SharedPostPreview(post: post),
                if (post.mediaUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: PostMedia(
                      url: post.mediaUrl!,
                      type: post.mediaType,
                      errorHeight: 150,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                if (post.likeCount > 0 || post.dislikeCount > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        if (post.likeCount > 0) ...[
                          const Icon(
                            Icons.thumb_up,
                            size: 14,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${post.likeCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                        if (post.likeCount > 0 && post.dislikeCount > 0)
                          const SizedBox(width: 10),
                        if (post.dislikeCount > 0) ...[
                          const Icon(
                            Icons.thumb_down,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${post.dislikeCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _reactionsStream,
                  builder: (context, reactionSnap) {
                    if (!reactionSnap.hasData) return const SizedBox.shrink();
                    final counts = <String, int>{};
                    for (final doc in reactionSnap.data!.docs) {
                      final type = doc.data()['type'] as String?;
                      if (type != null && type != 'like' && type != 'dislike') {
                        counts[type] = (counts[type] ?? 0) + 1;
                      }
                    }
                    final options = _reactionOptions
                        .where(
                          (option) =>
                              option.type != 'like' &&
                              (counts[option.type] ?? 0) > 0,
                        )
                        .toList();
                    if (options.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(
                        spacing: 8,
                        children: options
                            .map(
                              (option) => Text(
                                '${option.emoji} ${counts[option.type]}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _myReactionStream,
                  builder: (context, snap) {
                    final myType = snap.data?.data()?['type'] as String?;
                    _ReactionOption? selectedReaction;
                    for (final option in _reactionOptions) {
                      if (option.type == myType) selectedReaction = option;
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.thumb_up,
                            label: selectedReaction?.label ?? 'Like',
                            emoji: selectedReaction?.type == 'like'
                                ? null
                                : selectedReaction?.emoji,
                            active: myType != null && myType != 'dislike',
                            onTap: () => _react('like'),
                            onLongPress: _openReactionPicker,
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.thumb_down,
                            label: 'Dislike',
                            active: myType == 'dislike',
                            onTap: () => _react('dislike'),
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.comment_outlined,
                            label: 'Comment',
                            active: false,
                            onTap: _openComments,
                          ),
                        ),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.share_outlined,
                            label: 'Share',
                            active: false,
                            onTap: _sharePost,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    String? emoji,
    VoidCallback? onLongPress,
  }) {
    final color = active ? Colors.blue : Colors.black54;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (emoji != null)
              Text(emoji, style: const TextStyle(fontSize: 18))
            else
              Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditPostDialog extends StatefulWidget {
  final Post post;
  final PostService postService;

  const EditPostDialog({required this.post, required this.postService});

  @override
  State<EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<EditPostDialog> {
  late final TextEditingController _contentController;
  late String _audience;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.post.content);
    _audience = widget.post.audience;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.postService.updatePost(
        widget.post.id,
        _contentController.text.trim(),
        audience: widget.post.pageId == null ? _audience : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกโพสต์ไม่สำเร็จ: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แก้ไขโพสต์'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _contentController,
              autofocus: true,
              minLines: 3,
              maxLines: 7,
              maxLength: 10000,
              decoration: const InputDecoration(
                labelText: 'ข้อความ',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            if (widget.post.pageId == null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _audience,
                decoration: const InputDecoration(
                  labelText: 'ใครเห็นโพสต์นี้ได้บ้าง',
                  border: OutlineInputBorder(),
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
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) setState(() => _audience = value);
                      },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}

class _ReshareOptions {
  final String caption;
  final String audience;
  const _ReshareOptions(this.caption, this.audience);
}

class _ReshareDialog extends StatefulWidget {
  const _ReshareDialog();

  @override
  State<_ReshareDialog> createState() => _ReshareDialogState();
}

class _ReshareDialogState extends State<_ReshareDialog> {
  final _caption = TextEditingController();
  String _audience = 'public';

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('แชร์ลงฟีด'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _caption,
          maxLength: 10000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'เขียนข้อความประกอบโพสต์นี้',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _audience,
          decoration: const InputDecoration(
            labelText: 'ผู้ชม',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'public', child: Text('สาธารณะ')),
            DropdownMenuItem(value: 'friends', child: Text('เพื่อน')),
            DropdownMenuItem(value: 'private', child: Text('ส่วนตัว')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _audience = value);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _ReshareOptions(_caption.text.trim(), _audience),
        ),
        child: const Text('แชร์'),
      ),
    ],
  );
}

class _SharedPostPreview extends StatelessWidget {
  final Post post;
  const _SharedPostPreview({required this.post});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE0E0E0)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((post.sharedContent ?? '').isNotEmpty)
          Text(post.sharedContent!, style: const TextStyle(fontSize: 14)),
        if (post.sharedMediaUrl != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: PostMedia(
              url: post.sharedMediaUrl!,
              type: post.sharedMediaType,
              errorHeight: 150,
            ),
          ),
        ],
      ],
    ),
  );
}

class _CommentsSheet extends StatefulWidget {
  final String postId;
  final String postOwnerId;
  final String currentUid;
  final PostService postService;

  const _CommentsSheet({
    required this.postId,
    required this.postOwnerId,
    required this.currentUid,
    required this.postService,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _editComment(String commentId, String oldText) async {
    final controller = TextEditingController(text: oldText);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('แก้ไขความคิดเห็น'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 2000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || updated.isEmpty) return;
    try {
      await widget.postService.updateComment(
        postId: widget.postId,
        commentId: commentId,
        text: updated,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('แก้ไขความคิดเห็นไม่สำเร็จ: $error')),
        );
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบความคิดเห็นนี้?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.postService.deleteComment(
        postId: widget.postId,
        commentId: commentId,
      );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ลบความคิดเห็นไม่สำเร็จ: $error')),
        );
    }
  }

  Future<void> _reportComment(String commentId) async {
    try {
      await widget.postService.reportTarget(
        targetType: 'comment',
        targetId: '${widget.postId}_$commentId',
        reporterId: widget.currentUid,
        reason: 'ความคิดเห็นไม่เหมาะสม',
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งรายงานความคิดเห็นแล้ว')),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ส่งรายงานไม่สำเร็จ: $error')));
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.postService.addComment(
        postId: widget.postId,
        authorId: widget.currentUid,
        text: text,
      );
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('คอมเมนต์ไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: 460,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'ความคิดเห็น',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: widget.postService.commentsStream(widget.postId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text('ยังไม่มีคอมเมนต์'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final data = docs[i].data();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(uid: data['authorId'] ?? '', radius: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F2F5),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AuthorName(
                                      uid: data['authorId'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      data['text'] ?? '',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (data['authorId'] == widget.currentUid ||
                                widget.postOwnerId == widget.currentUid)
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit')
                                    _editComment(
                                      docs[i].id,
                                      data['text'] ?? '',
                                    );
                                  if (value == 'delete')
                                    _deleteComment(docs[i].id);
                                },
                                itemBuilder: (_) => [
                                  if (data['authorId'] == widget.currentUid)
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('แก้ไข'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('ลบ'),
                                  ),
                                ],
                              )
                            else
                              PopupMenuButton<String>(
                                onSelected: (_) => _reportComment(docs[i].id),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'report',
                                    child: Text('รายงานความคิดเห็น'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'แสดงความคิดเห็น...',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF0F2F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send, color: Colors.blue),
                      onPressed: _sending ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  final String postId;
  final String currentUid;
  final PostService postService;

  const _ReportDialog({
    required this.postId,
    required this.currentUid,
    required this.postService,
  });

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _reason = 'สแปม';
  bool _sending = false;

  final _reasons = ['สแปม', 'เนื้อหาไม่เหมาะสม', 'ความรุนแรง/คุกคาม', 'อื่นๆ'];

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await widget.postService.reportPost(
        postId: widget.postId,
        reporterId: widget.currentUid,
        reason: _reason,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งรายงานแล้ว ขอบคุณที่แจ้งให้ทราบ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งรายงานไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('รายงานโพสต์'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _reasons
            .map(
              (r) => RadioListTile<String>(
                title: Text(r),
                value: r,
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v!),
              ),
            )
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ส่งรายงาน'),
        ),
      ],
    );
  }
}

/// ล้าง cache ชื่อของ uid นี้ (เรียกหลังแก้ไขโปรไฟล์)
void invalidateAuthorName(String uid) => _AuthorNameState._cache.remove(uid);
