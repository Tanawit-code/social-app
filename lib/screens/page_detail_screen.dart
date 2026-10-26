import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/page_service.dart';
import '../services/post_service.dart';
import '../models/post_model.dart';
import '../services/storage_service.dart';
import '../utils/image_data.dart';
import '../widgets/user_avatar.dart';
import 'home_feed_screen.dart' show AuthorName, PostCard;
import 'create_post_screen.dart';

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

  void _toast(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

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
    } catch (e) { _toast(e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _approve(String uid) async {
    try { await _service.approveRequest(widget.pageId, _uid, uid); _toast('อนุมัติสมาชิกแล้ว'); }
    catch (e) { _toast(e.toString().replaceFirst('Exception: ', '')); }
  }

  Future<void> _changePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 60, maxWidth: 640, maxHeight: 640);
      if (picked == null) return;
      setState(() => _busy = true);
      final bytes = await picked.readAsBytes();
      final photoUrl = await StorageService().uploadCoverImageBytes(bytes: bytes, uid: _uid);
      await _service.updatePagePhoto(pageId: widget.pageId, ownerId: _uid, photoUrl: photoUrl);
      _toast('รูปเพจถูกเปลี่ยนแล้ว');
    } catch (e) { _toast(e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _compose() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CreatePostScreen(pageId: widget.pageId)));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _service.page(widget.pageId),
    builder: (context, pageSnap) {
      if (pageSnap.hasError) return Scaffold(appBar: AppBar(), body: Center(child: Text('โหลดเพจไม่สำเร็จ: ${pageSnap.error}')));
      if (!pageSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final data = pageSnap.data!.data();
      if (data == null) return const Scaffold(body: Center(child: Text('ไม่พบเพจนี้')));
      final name = (data['name'] ?? 'เพจ') as String;
      final description = (data['description'] ?? '') as String;
      final isPrivate = data['privacy'] == 'private';
      final ownerId = (data['ownerId'] ?? '') as String;
      final members = List<String>.from(data['memberIds'] ?? const []);
      final requests = List<String>.from(data['pendingRequests'] ?? const []);
      final isOwner = ownerId == _uid;
      final isMember = members.contains(_uid);
      final canViewPosts = !isPrivate || isMember;

      return Scaffold(
        appBar: AppBar(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
          if (isOwner) IconButton(tooltip: 'เปลี่ยนรูปเพจ', onPressed: _busy ? null : _changePhoto, icon: const Icon(Icons.edit_outlined)),
        ]),
        floatingActionButton: isMember ? FloatingActionButton.extended(onPressed: _compose, icon: const Icon(Icons.edit), label: const Text('เขียนโพสต์')) : null,
        body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: CircleAvatar(radius: 38, backgroundColor: const Color(0xFFE3F2FD), backgroundImage: imageProviderFor(data['photoUrl'] as String?), child: (data['photoUrl'] as String? ?? '').isEmpty ? const Icon(Icons.flag_outlined, size: 34, color: Color(0xFF1877F2)) : null)),
            const SizedBox(height: 12),
            Row(children: [Icon(isPrivate ? Icons.lock_outline : Icons.public, color: const Color(0xFF1877F2)), const SizedBox(width: 8), Text(isPrivate ? 'เพจส่วนตัว' : 'เพจสาธารณะ', style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text('${members.length} สมาชิก', style: const TextStyle(color: Colors.black54))]),
            if (description.isNotEmpty) ...[const SizedBox(height: 10), Text(description)],
            if (!isMember && !isPrivate) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: _busy ? null : () => _join(isPrivate: false), icon: const Icon(Icons.group_add), label: const Text('เข้าร่วมเพจเพื่อโพสต์'))],
            if (!isMember && isPrivate) ...[const SizedBox(height: 12), requests.contains(_uid) ? const Chip(avatar: Icon(Icons.hourglass_top, size: 18), label: Text('รออนุมัติคำขอเข้าร่วม')) : OutlinedButton.icon(onPressed: _busy ? null : () => _join(isPrivate: true), icon: const Icon(Icons.lock_open), label: const Text('ขอเข้าร่วมเพื่อดูโพสต์'))],
          ]))),
          if (isOwner && requests.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('คำขอเข้าร่วม (${requests.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            ...requests.map((uid) => ListTile(dense: true, leading: UserAvatar(uid: uid, radius: 18), title: AuthorName(uid: uid), trailing: TextButton(onPressed: () => _approve(uid), child: const Text('อนุมัติ')))),
          ]))),
          if (!canViewPosts) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('โพสต์ของเพจส่วนตัวจะแสดงหลังเจ้าของอนุมัติคำขอเข้าร่วม'))),
          if (canViewPosts) StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _service.posts(widget.pageId),
            builder: (context, postsSnap) {
              if (postsSnap.hasError) return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('โหลดโพสต์ไม่สำเร็จ: ${postsSnap.error}')));
              if (!postsSnap.hasData) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
              if (postsSnap.data!.docs.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: Text('ยังไม่มีโพสต์ในเพจนี้'))));
              final docs = postsSnap.data!.docs.toList()
                ..sort((a, b) {
                  final ta = a.data()['createdAt'] as Timestamp?;
                  final tb = b.data()['createdAt'] as Timestamp?;
                  return (tb?.millisecondsSinceEpoch ?? 0).compareTo(ta?.millisecondsSinceEpoch ?? 0);
                });
              final postService = PostService();
              return Column(children: docs.map((doc) {
                final post = Post.fromDoc(doc);
                return Padding(
                  key: ValueKey(post.id),
                  padding: const EdgeInsets.only(top: 8),
                  child: PostCard(post: post, currentUid: _uid, postService: postService),
                );
              }).toList());
            },
          ),
        ]),
      );
    },
  );
}
