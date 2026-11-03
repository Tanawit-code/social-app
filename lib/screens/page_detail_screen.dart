import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/report_dialog.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/page_service.dart';
import '../services/post_service.dart';
import '../models/post_model.dart';
import '../services/storage_service.dart';
import '../utils/image_data.dart';
import 'home_feed_screen.dart' show AuthorName, PostCard;
import 'create_post_screen.dart';
import 'members_list_screen.dart';
import 'page_moderation_screen.dart';
import '../widgets/join_requests_section.dart';

class PageDetailScreen extends StatefulWidget {
  final String pageId;
  const PageDetailScreen({required this.pageId, super.key});
  @override
  State<PageDetailScreen> createState() => _PageDetailScreenState();
}

class _PageDetailScreenState extends State<PageDetailScreen> {
  final _service = PageService();
  final _uid = AuthService().currentUser?.uid ?? '';
  bool _busy = false;

  void _toast(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _join({required bool isPrivate}) async {
    setState(() => _busy = true);
    try {
      if (isPrivate) {
        await _service.requestToJoin(widget.pageId, _uid);
        _toast('ส่งคำขอเข้าร่วมแล้ว');
      } else {
        await _service.joinPublicPage(widget.pageId, _uid);
        _toast('เข้าร่วมเพจแล้ว คุณโพสต์ได้แล้ว');
      }
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRequest() async {
    setState(() => _busy = true);
    try {
      await _service.cancelRequest(widget.pageId, _uid);
      _toast('ยกเลิกคำขอแล้ว');
    } catch (e) {
      _toast(
        'ยกเลิกคำขอไม่สำเร็จ: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String okLabel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _leave() async {
    if (!await _confirm(
      'ออกจากเพจ?',
      'คุณจะไม่ได้เป็นสมาชิกและโพสต์ในเพจนี้ไม่ได้ (เพจส่วนตัวต้องขอเข้าร่วมใหม่)',
      'ออกจากเพจ',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.leavePage(widget.pageId, _uid);
      _toast('ออกจากเพจแล้ว');
    } catch (e) {
      _toast(
        'ออกจากเพจไม่สำเร็จ: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePage() async {
    if (!await _confirm(
      'ลบเพจนี้ถาวร?',
      'เพจและโพสต์ทั้งหมดในเพจจะถูกลบและกู้คืนไม่ได้',
      'ลบเพจ',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.deletePage(widget.pageId, _uid);
      if (!mounted) return;
      _toast('ลบเพจแล้ว');
      Navigator.pop(context);
    } catch (e) {
      _toast(
        'ลบเพจไม่สำเร็จ: ${e.toString().replaceFirst('Exception: ', '')}',
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 640,
        maxHeight: 640,
      );
      if (picked == null) return;
      setState(() => _busy = true);
      final bytes = await picked.readAsBytes();
      final photoUrl = await StorageService().uploadCoverImageBytes(
        bytes: bytes,
        uid: _uid,
      );
      await _service.updatePagePhoto(
        pageId: widget.pageId,
        ownerId: _uid,
        photoUrl: photoUrl,
      );
      _toast('รูปเพจถูกเปลี่ยนแล้ว');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compose() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(pageId: widget.pageId),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _service.page(widget.pageId),
    builder: (context, pageSnap) {
      if (pageSnap.hasError)
        return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('โหลดเพจไม่สำเร็จ: ${pageSnap.error}')),
        );
      if (!pageSnap.hasData)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final data = pageSnap.data!.data();
      if (data == null)
        return const Scaffold(body: Center(child: Text('ไม่พบเพจนี้')));
      final name = (data['name'] ?? 'เพจ') as String;
      final description = (data['description'] ?? '') as String;
      final isPrivate = data['privacy'] == 'private';
      final ownerId = (data['ownerId'] ?? '') as String;
      final members = List<String>.from(data['memberIds'] ?? const []);
      final requests = List<String>.from(data['pendingRequests'] ?? const []);
      final moderators = List<String>.from(data['moderatorIds'] ?? const []);
      final banned = List<String>.from(data['bannedIds'] ?? const []);
      final isOwner = ownerId == _uid;
      final isMember = members.contains(_uid);
      final isBanned = banned.contains(_uid);
      final canModerate = isOwner || moderators.contains(_uid);
      final canViewPosts = !isBanned && (!isPrivate || isMember);

      return Scaffold(
        appBar: AppBar(
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (canModerate)
              IconButton(
                tooltip: 'เครื่องมือผู้ดูแล',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PageModerationScreen(pageId: widget.pageId),
                  ),
                ),
                icon: const Icon(Icons.shield_outlined),
              ),
            if (isOwner)
              IconButton(
                tooltip: 'เปลี่ยนรูปเพจ',
                onPressed: _busy ? null : _changePhoto,
                icon: const Icon(Icons.edit_outlined),
              ),
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (value) {
                if (value == 'leave') _leave();
                if (value == 'delete') _deletePage();
                if (value == 'report') {
                  showReportFlow(
                    context,
                    title: 'รายงานเพจ',
                    targetType: 'page',
                    targetId: widget.pageId,
                    reportedUid: ownerId,
                  );
                }
              },
              itemBuilder: (_) => [
                if (isMember && !isOwner)
                  const PopupMenuItem(
                    value: 'leave',
                    child: Text('ออกจากเพจ'),
                  ),
                if (isOwner)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      'ลบเพจ',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                if (!isOwner)
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('รายงานเพจ'),
                  ),
              ],
            ),
          ],
        ),
        floatingActionButton: isMember
            ? FloatingActionButton.extended(
                onPressed: _compose,
                icon: const Icon(Icons.edit),
                label: const Text('เขียนโพสต์'),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: const Color(0xFFE3F2FD),
                        backgroundImage: imageProviderFor(
                          data['photoUrl'] as String?,
                        ),
                        child: (data['photoUrl'] as String? ?? '').isEmpty
                            ? Icon(
                                Icons.flag_outlined,
                                size: 34,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          isPrivate ? Icons.lock_outline : Icons.public,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isPrivate ? 'เพจส่วนตัว' : 'เพจสาธารณะ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (canViewPosts)
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MembersListScreen(
                                  title: 'สมาชิก $name',
                                  members: _service
                                      .page(widget.pageId)
                                      .map(
                                        (s) =>
                                            List<String>.from(
                                                  s.data()?['memberIds'] ??
                                                      const [],
                                                )
                                                .map(
                                                  (u) => MemberEntry(
                                                    u,
                                                    u == ownerId
                                                        ? 'owner'
                                                        : List<String>.from(
                                                                s.data()?['moderatorIds'] ??
                                                                    const [],
                                                              ).contains(u)
                                                        ? 'moderator'
                                                        : 'member',
                                                  ),
                                                )
                                                .toList(),
                                      ),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.people_outline, size: 18),
                            label: Text('${members.length} สมาชิก'),
                          )
                        else
                          Text(
                            isBanned
                                ? 'คุณถูกแบนจากเพจนี้'
                                : 'เข้าร่วมเพื่อดูสมาชิก',
                            style: const TextStyle(color: Colors.black54),
                          ),
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(description),
                    ],
                    if (isBanned) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.block,
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'คุณถูกแบนจากเพจนี้ จึงไม่สามารถเข้าร่วม ดู หรือโพสต์ได้',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (isMember && !isOwner) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _leave,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('ออกจากเพจ'),
                      ),
                    ],
                    if (!isMember && !isBanned && !isPrivate) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _join(isPrivate: false),
                        icon: const Icon(Icons.group_add),
                        label: const Text('เข้าร่วมเพจเพื่อโพสต์'),
                      ),
                    ],
                    if (!isMember && !isBanned && isPrivate) ...[
                      const SizedBox(height: 12),
                      requests.contains(_uid)
                          ? OutlinedButton.icon(
                              onPressed: _busy ? null : _cancelRequest,
                              icon: const Icon(Icons.hourglass_top, size: 18),
                              label: const Text(
                                'รออนุมัติ · แตะเพื่อยกเลิกคำขอ',
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _join(isPrivate: true),
                              icon: const Icon(Icons.lock_open),
                              label: const Text('ขอเข้าร่วมเพื่อดูโพสต์'),
                            ),
                    ],
                  ],
                ),
              ),
            ),
            if (canModerate) ...[
              const SizedBox(height: 8),
              JoinRequestsSection(
                title: 'คำขอเข้าร่วมเพจ',
                kindLabel: 'เพจ',
                requests: requests.map((u) => JoinRequestItem(u)).toList(),
                onApprove: (u) =>
                    _service.approveRequest(widget.pageId, _uid, u),
                onDecline: (u) =>
                    _service.declineRequest(widget.pageId, _uid, u),
              ),
            ],
            if (!canViewPosts)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    isBanned
                        ? 'คุณไม่มีสิทธิ์ดูโพสต์ของเพจนี้'
                        : 'โพสต์ของเพจส่วนตัวจะแสดงหลังเจ้าของอนุมัติคำขอเข้าร่วม',
                  ),
                ),
              ),
            if (canViewPosts)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.posts(widget.pageId),
                builder: (context, postsSnap) {
                  if (postsSnap.hasError)
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('โหลดโพสต์ไม่สำเร็จ: ${postsSnap.error}'),
                      ),
                    );
                  if (!postsSnap.hasData)
                    return const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  if (postsSnap.data!.docs.isEmpty)
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: Text('ยังไม่มีโพสต์ในเพจนี้')),
                      ),
                    );
                  final docs = postsSnap.data!.docs.toList()
                    ..sort((a, b) {
                      final ta = a.data()['createdAt'] as Timestamp?;
                      final tb = b.data()['createdAt'] as Timestamp?;
                      return (tb?.millisecondsSinceEpoch ?? 0).compareTo(
                        ta?.millisecondsSinceEpoch ?? 0,
                      );
                    });
                  final postService = PostService();
                  return Column(
                    children: docs
                        .where(
                          (d) =>
                              canModerate ||
                              !Post.fromDoc(d).isHiddenFor(_uid),
                        )
                        .map((doc) {
                      final post = Post.fromDoc(doc);
                      return Padding(
                        key: ValueKey(post.id),
                        padding: const EdgeInsets.only(top: 8),
                        child: PostCard(
                          post: post,
                          currentUid: _uid,
                          postService: postService,
                          canModerate: canModerate,
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}
