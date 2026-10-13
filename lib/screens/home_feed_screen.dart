import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../services/notification_service.dart';
import 'create_post_screen.dart';
import 'profile_screen.dart';
import '../widgets/user_avatar.dart';
import '../utils/image_data.dart';

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
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.pushNamed(context, '/search'),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.pushNamed(context, '/chats'),
          ),
          StreamBuilder<int>(
            stream: NotificationService().unreadCount(uid),
            builder: (context, s) => Badge(
              isLabelVisible: (s.data ?? 0) > 0,
              label: Text('${s.data ?? 0}'),
              child: IconButton(
                icon: const Icon(Icons.notifications_none),
                onPressed: () =>
                    Navigator.pushNamed(context, '/notifications'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.pushNamed(context, '/profile'),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: StreamBuilder<List<Post>>(
        stream: _postService.feedStream(),
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
                    child: _PostCard(
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

class _PostCard extends StatefulWidget {
  final Post post;
  final String currentUid;
  final PostService postService;

  const _PostCard({
    required this.post,
    required this.currentUid,
    required this.postService,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
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
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'report') _report();
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
                          else
                            const PopupMenuItem(
                              value: 'report',
                              child: Text('รายงานโพสต์'),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (post.content.isNotEmpty)
                  Text(post.content, style: const TextStyle(fontSize: 15)),
                if (post.mediaUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AppImage(
                      src: post.mediaUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
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
                const Divider(height: 1),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _myReactionStream,
                  builder: (context, snap) {
                    final myType = snap.data?.data()?['type'] as String?;
                    return Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.thumb_up,
                            label: 'Like',
                            active: myType == 'like',
                            onTap: () => _react('like'),
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
                            onTap: () {},
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
  }) {
    final color = active ? Colors.blue : Colors.black54;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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

class _CommentsSheet extends StatefulWidget {
  final String postId;
  final String currentUid;
  final PostService postService;

  const _CommentsSheet({
    required this.postId,
    required this.currentUid,
    required this.postService,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

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
                            UserAvatar(
                              uid: data['authorId'] ?? '',
                              radius: 16,
                            ),
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
