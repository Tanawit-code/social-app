import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../models/community_model.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../services/storage_service.dart';
import '../services/video_upload_service.dart';
import '../widgets/post_media.dart';
import '../widgets/user_avatar.dart';
import 'community_moderation_screen.dart';

class CommunityDetailScreen extends StatefulWidget {
  final Community community;
  const CommunityDetailScreen({required this.community, super.key});
  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  final _uid = AuthService().currentUser?.uid ?? '';
  final _service = CommunityService();
  final _text = TextEditingController();
  Uint8List? _imageBytes;
  Uint8List? _videoBytes;
  String? _videoName;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      await _service.join(widget.community, _uid);
      _message(
        widget.community.privacy == 'private'
            ? 'ส่งคำขอเข้าร่วมแล้ว'
            : 'เข้าร่วมชุมชนแล้ว',
      );
    } catch (e) {
      _message('เข้าร่วมไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty && _imageBytes == null && _videoBytes == null)
      return;
    setState(() => _busy = true);
    try {
      String? mediaUrl;
      String? mediaType;
      if (_imageBytes != null) {
        mediaUrl = await StorageService().uploadPostImageBytes(
          bytes: _imageBytes!,
          uid: _uid,
        );
        mediaType = 'image';
      } else if (_videoBytes != null) {
        mediaUrl = await VideoUploadService().uploadVideoBytes(
          bytes: _videoBytes!,
          filename: _videoName ?? 'community-video.mp4',
        );
        mediaType = 'video';
      }
      await _service.createPost(
        communityId: widget.community.id,
        authorId: _uid,
        text: _text.text,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      _text.clear();
      if (mounted)
        setState(() {
          _imageBytes = null;
          _videoBytes = null;
          _videoName = null;
        });
    } catch (e) {
      _message('โพสต์ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 55,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted)
        setState(() {
          _imageBytes = bytes;
          _videoBytes = null;
          _videoName = null;
        });
    } catch (e) {
      _message('เลือกรูปไม่สำเร็จ: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: VideoUploadService.maxSeconds),
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > VideoUploadService.maxBytes)
        throw Exception(
          'วิดีโอต้องไม่เกิน ${VideoUploadService.maxBytes ~/ (1024 * 1024)} MB',
        );
      if (mounted)
        setState(() {
          _videoBytes = bytes;
          _videoName = file.name;
          _imageBytes = null;
        });
    } catch (e) {
      _message('เลือกวิดีโอไม่สำเร็จ: $e');
    }
  }

  Future<void> _report(String postId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('รายงานโพสต์'),
        children: ['สแปม', 'เนื้อหาไม่เหมาะสม', 'คุกคามหรือทำร้ายผู้อื่น']
            .map(
              (value) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, value),
                child: Text(value),
              ),
            )
            .toList(),
      ),
    );
    if (reason == null) return;
    try {
      await _service.reportPost(
        communityId: widget.community.id,
        postId: postId,
        reporterId: _uid,
        reason: reason,
      );
      _message('ส่งรายงานให้ผู้ดูแลแล้ว');
    } catch (e) {
      _message('ส่งรายงานไม่สำเร็จ: $e');
    }
  }

  Future<void> _editPost(String postId, String oldText) async {
    final controller = TextEditingController(text: oldText);
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขโพสต์'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          maxLength: 5000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await _service.editPost(
          communityId: widget.community.id,
          postId: postId,
          text: controller.text,
        );
      } catch (e) {
        _message('แก้ไขโพสต์ไม่สำเร็จ: $e');
      }
    }
    controller.dispose();
  }

  void _openComments({
    required String postId,
    required String postOwnerId,
    required bool canModerate,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CommunityCommentsSheet(
        communityId: widget.community.id,
        postId: postId,
        postOwnerId: postOwnerId,
        canDeleteOthers: canModerate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final communityRef = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.community.id);
    final memberRef = communityRef.collection('members').doc(_uid);
    final requestRef = communityRef.collection('joinRequests').doc(_uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: memberRef.snapshots(),
      builder: (context, memberSnap) {
        final membership = memberSnap.data?.data();
        final isMember = membership != null;
        final role = membership?['role'] as String? ?? 'member';
        final canModerate = role == 'owner' || role == 'moderator';
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.community.name),
            actions: [
              if (canModerate)
                IconButton(
                  tooltip: 'เครื่องมือผู้ดูแล',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityModerationScreen(
                        community: widget.community,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'leave') {
                    try {
                      await _service.leave(widget.community.id, _uid);
                    } catch (e) {
                      _message('ออกจากชุมชนไม่สำเร็จ: $e');
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (isMember && role != 'owner')
                    const PopupMenuItem(
                      value: 'leave',
                      child: Text('ออกจากชุมชน'),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.community.privacy == 'private'
                              ? Icons.lock_outline
                              : Icons.public,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.community.privacy == 'private'
                              ? 'ชุมชนส่วนตัว'
                              : 'ชุมชนสาธารณะ',
                        ),
                        const Spacer(),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: communityRef
                              .collection('members')
                              .snapshots(),
                          builder: (context, snap) =>
                              Text('${snap.data?.size ?? 0} สมาชิก'),
                        ),
                      ],
                    ),
                    if (widget.community.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(widget.community.description),
                      ),
                  ],
                ),
              ),
              if (!isMember)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: requestRef.snapshots(),
                  builder: (context, requestSnap) {
                    final requested = requestSnap.data?.exists ?? false;
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : requested
                              ? () => _service.cancelRequest(
                                  widget.community.id,
                                  _uid,
                                )
                              : _join,
                          icon: Icon(
                            requested
                                ? Icons.hourglass_top
                                : Icons.group_add_outlined,
                          ),
                          label: Text(
                            requested
                                ? 'ยกเลิกคำขอเข้าร่วม'
                                : widget.community.privacy == 'private'
                                ? 'ขอเข้าร่วมชุมชน'
                                : 'เข้าร่วมชุมชน',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (isMember)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          UserAvatar(uid: _uid),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _text,
                              maxLength: 5000,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText: 'เขียนโพสต์ในชุมชน',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _busy ? null : _post,
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                      if (_imageBytes != null)
                        Image.memory(_imageBytes!, height: 120),
                      if (_videoName != null)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.videocam),
                          title: Text(
                            _videoName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            onPressed: () => setState(() {
                              _videoBytes = null;
                              _videoName = null;
                            }),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _busy ? null : _pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('รูป'),
                          ),
                          TextButton.icon(
                            onPressed: _busy ? null : _pickVideo,
                            icon: const Icon(Icons.video_library_outlined),
                            label: const Text('วิดีโอ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: !isMember && widget.community.privacy == 'private'
                    ? const Center(
                        child: Text(
                          'โพสต์จะแสดงหลังจากได้รับอนุมัติเข้าร่วมชุมชน',
                        ),
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: communityRef
                            .collection('posts')
                            .orderBy('createdAt', descending: true)
                            .limit(60)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError)
                            return Center(
                              child: Text(
                                'โหลดโพสต์ชุมชนไม่สำเร็จ: ${snap.error}',
                              ),
                            );
                          if (!snap.hasData)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (snap.data!.docs.isEmpty)
                            return const Center(
                              child: Text('ชุมชนนี้ยังไม่มีโพสต์'),
                            );
                          return ListView.builder(
                            itemCount: snap.data!.docs.length,
                            itemBuilder: (context, index) {
                              final doc = snap.data!.docs[index];
                              final data = doc.data();
                              final authorId =
                                  data['authorId'] as String? ?? '';
                              return Card(
                                margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          UserAvatar(uid: authorId, radius: 18),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _MemberName(uid: authorId),
                                                Text(
                                                  _communityTime(
                                                    data['createdAt']
                                                        as Timestamp?,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (data['isPinned'] == true)
                                            const Icon(
                                              Icons.push_pin_outlined,
                                              size: 18,
                                            ),
                                          PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'edit')
                                                _editPost(
                                                  doc.id,
                                                  data['text'] as String? ?? '',
                                                );
                                              if (value == 'delete')
                                                _service.deletePost(
                                                  widget.community.id,
                                                  doc.id,
                                                );
                                              if (value == 'pin')
                                                _service.pinPost(
                                                  widget.community.id,
                                                  doc.id,
                                                  data['isPinned'] != true,
                                                );
                                              if (value == 'report')
                                                _report(doc.id);
                                            },
                                            itemBuilder: (_) => [
                                              if (authorId == _uid)
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('แก้ไขโพสต์'),
                                                ),
                                              if (canModerate ||
                                                  authorId == _uid)
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('ลบโพสต์'),
                                                ),
                                              if (canModerate)
                                                PopupMenuItem(
                                                  value: 'pin',
                                                  child: Text(
                                                    data['isPinned'] == true
                                                        ? 'เลิกปักหมุด'
                                                        : 'ปักหมุด',
                                                  ),
                                                ),
                                              if (isMember && authorId != _uid)
                                                const PopupMenuItem(
                                                  value: 'report',
                                                  child: Text('รายงาน'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if ((data['text'] as String? ?? '')
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            data['text'] as String? ?? '',
                                          ),
                                        ),
                                      if (data['mediaUrl'] is String)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: PostMedia(
                                            url: data['mediaUrl'] as String,
                                            type: data['mediaType'] as String?,
                                          ),
                                        ),
                                      _CommunityPostActions(
                                        communityId: widget.community.id,
                                        postId: doc.id,
                                        uid: _uid,
                                        likeCount:
                                            (data['likeCount'] as num?)
                                                ?.toInt() ??
                                            0,
                                        dislikeCount:
                                            (data['dislikeCount'] as num?)
                                                ?.toInt() ??
                                            0,
                                        onComments: () => _openComments(
                                          postId: doc.id,
                                          postOwnerId: authorId,
                                          canModerate: canModerate,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberName extends StatelessWidget {
  final String uid;
  const _MemberName({required this.uid});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) => Text(
          snap.data?.data()?['name'] as String? ?? 'สมาชิก',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
}

String _communityTime(Timestamp? timestamp) {
  if (timestamp == null) return 'เพิ่งโพสต์';
  final age = DateTime.now().difference(timestamp.toDate());
  if (age.inSeconds < 60) return 'เมื่อสักครู่';
  if (age.inMinutes < 60) return '${age.inMinutes} นาทีที่แล้ว';
  if (age.inHours < 24) return '${age.inHours} ชั่วโมงที่แล้ว';
  if (age.inDays < 7) return '${age.inDays} วันที่แล้ว';
  final date = timestamp.toDate();
  return '${date.day}/${date.month}/${date.year}';
}

class _CommunityPostActions extends StatelessWidget {
  final String communityId;
  final String postId;
  final String uid;
  final int likeCount;
  final int dislikeCount;
  final VoidCallback onComments;
  const _CommunityPostActions({
    required this.communityId,
    required this.postId,
    required this.uid,
    required this.likeCount,
    required this.dislikeCount,
    required this.onComments,
  });

  @override
  Widget build(BuildContext context) {
    final service = CommunityService();
    final post = service.postDocument(communityId, postId);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              if (likeCount > 0)
                const Icon(Icons.thumb_up, size: 15, color: Colors.blue),
              if (likeCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '$likeCount',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if (dislikeCount > 0) ...[
                if (likeCount > 0) const SizedBox(width: 8),
                const Icon(Icons.thumb_down, size: 15, color: Colors.grey),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '$dislikeCount',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const Spacer(),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: service.comments(communityId, postId),
                builder: (context, snap) => Text(
                  '${snap.data?.size ?? 0} comments',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 14),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: post.collection('reactions').doc(uid).snapshots(),
          builder: (context, snap) {
            final type = snap.data?.data()?['type'] as String?;
            return Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => service.setReaction(
                      communityId: communityId,
                      postId: postId,
                      uid: uid,
                      type: 'like',
                    ),
                    icon: Icon(
                      Icons.thumb_up_alt_outlined,
                      color: type == 'like' ? Colors.blue : Colors.grey,
                    ),
                    label: Text(
                      'Like',
                      style: TextStyle(
                        color: type == 'like'
                            ? Colors.blue
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => service.setReaction(
                      communityId: communityId,
                      postId: postId,
                      uid: uid,
                      type: 'dislike',
                    ),
                    icon: Icon(
                      Icons.thumb_down_alt_outlined,
                      color: type == 'dislike' ? Colors.blue : Colors.grey,
                    ),
                    label: Text(
                      'Dislike',
                      style: TextStyle(
                        color: type == 'dislike'
                            ? Colors.blue
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onComments,
                    icon: const Icon(Icons.mode_comment_outlined),
                    label: const Text('Comment'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CommunityCommentsSheet extends StatefulWidget {
  final String communityId;
  final String postId;
  final String postOwnerId;
  final bool canDeleteOthers;
  const _CommunityCommentsSheet({
    required this.communityId,
    required this.postId,
    required this.postOwnerId,
    required this.canDeleteOthers,
  });

  @override
  State<_CommunityCommentsSheet> createState() =>
      _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<_CommunityCommentsSheet> {
  final _uid = AuthService().currentUser?.uid ?? '';
  final _text = TextEditingController();
  final _service = CommunityService();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _service.addComment(
        communityId: widget.communityId,
        postId: widget.postId,
        authorId: _uid,
        text: _text.text,
      );
      _text.clear();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ส่งคอมเมนต์ไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(String commentId, String oldText) async {
    final controller = TextEditingController(text: oldText);
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขคอมเมนต์'),
        content: TextField(
          controller: controller,
          maxLength: 2000,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (save == true)
      await _service.editComment(
        communityId: widget.communityId,
        postId: widget.postId,
        commentId: commentId,
        text: controller.text,
      );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.of(context).size.height * .78,
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'คอมเมนต์',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _service.comments(widget.communityId, widget.postId),
            builder: (context, snap) {
              if (snap.hasError)
                return Center(
                  child: Text('โหลดคอมเมนต์ไม่สำเร็จ: ${snap.error}'),
                );
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty)
                return const Center(child: Text('ยังไม่มีคอมเมนต์'));
              return ListView(
                children: snap.data!.docs.map((doc) {
                  final data = doc.data();
                  final authorId = data['authorId'] as String? ?? '';
                  return ListTile(
                    leading: UserAvatar(uid: authorId, radius: 18),
                    title: _MemberName(uid: authorId),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['text'] as String? ?? ''),
                        Text(
                          _communityTime(data['createdAt'] as Timestamp?),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    trailing:
                        authorId == _uid ||
                            widget.canDeleteOthers ||
                            widget.postOwnerId == _uid
                        ? PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit')
                                _edit(doc.id, data['text'] as String? ?? '');
                              if (value == 'delete')
                                _service.deleteComment(
                                  communityId: widget.communityId,
                                  postId: widget.postId,
                                  commentId: doc.id,
                                );
                            },
                            itemBuilder: (_) => [
                              if (authorId == _uid)
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
                        : null,
                  );
                }).toList(),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    maxLength: 2000,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'เขียนคอมเมนต์',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
