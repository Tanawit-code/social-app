import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/community_model.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../screens/community_detail_screen.dart'
    show CommunityDetailScreen, CommunityPostScreen;
import '../screens/home_feed_screen.dart' show AuthorName;
import '../screens/page_detail_screen.dart' show PageDetailScreen;
import '../screens/post_detail_screen.dart' show PostDetailScreen;
import '../utils/mention.dart';

/// การ์ดโพสต์ที่แชร์เข้าแชท/กลุ่ม — ข้อความเก็บแค่ id ของโพสต์ (ดู ChatService.postRef)
/// เนื้อหาโหลดสดตอนแสดง จึงให้ Firestore rules เป็นตัวตัดสินสิทธิ์ดู:
///  - โพสต์ในชุมชน/เพจส่วนตัว: คนที่ยังไม่เป็นสมาชิกจะเห็นเป็นการ์ดล็อก (ไม่เห็นเนื้อหา)
///    กดเข้าไปได้ แต่จะไปที่หน้าชุมชน/เพจซึ่งต้องขอเข้าร่วมก่อนจึงจะดูโพสต์ได้
///  - โพสต์ที่ถูกลบแล้วจะแสดงว่า "โพสต์ถูกลบแล้ว"
class SharedPostCard extends StatefulWidget {
  final Map<String, dynamic> shared;
  final double width;
  const SharedPostCard({required this.shared, this.width = 260, super.key});

  @override
  State<SharedPostCard> createState() => _SharedPostCardState();
}

enum _Access { ok, locked, deleted }

class _SharedPostCardState extends State<SharedPostCard> {
  late Future<_Resolved> _future = _resolve();

  String get _kind => widget.shared['kind'] as String? ?? 'post';
  String get _postId => widget.shared['postId'] as String? ?? '';
  String? get _communityId => widget.shared['communityId'] as String?;
  String? get _pageId => widget.shared['pageId'] as String?;

  @override
  void didUpdateWidget(covariant SharedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shared['postId'] != widget.shared['postId'] ||
        oldWidget.shared['communityId'] != widget.shared['communityId'] ||
        oldWidget.shared['pageId'] != widget.shared['pageId']) {
      _future = _resolve();
    }
  }

  static bool _denied(Object e) =>
      e is FirebaseException && e.code == 'permission-denied';

  /// ชื่อ + ความเป็นส่วนตัวของชุมชน/เพจ (อ่านได้เสมอเมื่อล็อกอิน) ไว้แสดงบนการ์ดล็อก
  Future<Map<String, dynamic>?> _sourceInfo() async {
    try {
      if (_kind == 'community_post' && _communityId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('communities')
            .doc(_communityId)
            .get();
        return doc.data();
      }
      if (_pageId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('pages')
            .doc(_pageId)
            .get();
        return doc.data();
      }
    } catch (_) {}
    return null;
  }

  Future<_Resolved> _resolve() async {
    final db = FirebaseFirestore.instance;
    final source = await _sourceInfo();
    final sourceName = source?['name'] as String?;
    final sourcePrivate = source?['privacy'] == 'private';
    try {
      if (_kind == 'community_post') {
        final cid = _communityId;
        if (cid == null || _postId.isEmpty) {
          return _Resolved(_Access.deleted);
        }
        final doc = await db
            .collection('communities')
            .doc(cid)
            .collection('posts')
            .doc(_postId)
            .get();
        if (!doc.exists) return _Resolved(_Access.deleted, sourceName: sourceName);
        final data = doc.data()!;
        return _Resolved(
          _Access.ok,
          sourceName: sourceName,
          sourcePrivate: sourcePrivate,
          authorId: data['authorId'] as String? ?? '',
          text: data['text'] as String? ?? '',
          mediaUrl: data['mediaUrl'] as String?,
          mediaType: data['mediaType'] as String?,
        );
      }
      if (_postId.isEmpty) return _Resolved(_Access.deleted);
      final doc = await db.collection('posts').doc(_postId).get();
      if (!doc.exists) return _Resolved(_Access.deleted, sourceName: sourceName);
      final post = Post.fromDoc(doc);
      if (post.isHiddenFor(AuthService().currentUser?.uid ?? '')) {
        return _Resolved(_Access.deleted, sourceName: sourceName);
      }
      return _Resolved(
        _Access.ok,
        sourceName: sourceName,
        sourcePrivate: sourcePrivate,
        authorId: post.authorId,
        text: post.content.isNotEmpty
            ? post.content
            : (post.sharedContent ?? ''),
        mediaUrl: post.mediaUrl ?? post.sharedMediaUrl,
        mediaType: post.mediaType ?? post.sharedMediaType,
      );
    } catch (e) {
      if (_denied(e)) {
        return _Resolved(
          _Access.locked,
          sourceName: sourceName,
          sourcePrivate: sourcePrivate,
        );
      }
      return _Resolved(
        _Access.locked,
        sourceName: sourceName,
        sourcePrivate: sourcePrivate,
      );
    }
  }

  Future<void> _open(_Resolved r) async {
    final nav = Navigator.of(context);
    if (_kind == 'community_post' && _communityId != null) {
      if (r.access == _Access.ok) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => CommunityPostScreen(
              communityId: _communityId!,
              postId: _postId,
            ),
          ),
        );
        return;
      }
      // ยังไม่ได้เป็นสมาชิกชุมชนส่วนตัว: ไปหน้าชุมชน (มีปุ่มขอเข้าร่วม)
      try {
        final doc = await FirebaseFirestore.instance
            .collection('communities')
            .doc(_communityId)
            .get();
        if (!doc.exists) {
          _toast('ไม่พบชุมชนนี้ (อาจถูกลบแล้ว)');
          return;
        }
        nav.push(
          MaterialPageRoute(
            builder: (_) =>
                CommunityDetailScreen(community: Community.fromDoc(doc)),
          ),
        );
      } catch (e) {
        _toast('เปิดชุมชนไม่สำเร็จ: $e');
      }
      return;
    }
    if (r.access != _Access.ok && _pageId != null) {
      // เพจส่วนตัวที่ยังไม่ได้เป็นสมาชิก: ไปหน้าเพจ (มีปุ่มขอเข้าร่วม)
      nav.push(
        MaterialPageRoute(builder: (_) => PageDetailScreen(pageId: _pageId!)),
      );
      return;
    }
    nav.push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: _postId)),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _sourceLabel(_Resolved r) {
    final name = r.sourceName;
    if (_kind == 'community_post') {
      return name == null ? 'โพสต์ในชุมชน' : 'ชุมชน $name';
    }
    if (_kind == 'page_post' || _pageId != null) {
      return name == null ? 'โพสต์ในเพจ' : 'เพจ $name';
    }
    return 'โพสต์';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Resolved>(
      future: _future,
      builder: (context, snap) {
        final r = snap.data;
        return Container(
          width: widget.width,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: r == null || r.access == _Access.deleted
                ? null
                : () => _open(r),
            child: r == null
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _body(context, r),
          ),
        );
      },
    );
  }

  Widget _header(_Resolved r, {required IconData icon}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Colors.black54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _sourceLabel(r),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ],
    ),
  );

  Widget _body(BuildContext context, _Resolved r) {
    if (r.access == _Access.deleted) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: const [
            Icon(Icons.delete_outline, size: 18, color: Colors.black45),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'โพสต์ถูกลบแล้ว',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.black45,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (r.access == _Access.locked) {
      final isPrivateSource = r.sourcePrivate;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(r, icon: Icons.lock_outline),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPrivateSource
                      ? 'โพสต์นี้อยู่ในกลุ่มส่วนตัว'
                      : 'คุณไม่มีสิทธิ์ดูโพสต์นี้',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  isPrivateSource
                      ? 'ต้องขอเข้าร่วมก่อนจึงจะดูเนื้อหาได้ — กดเพื่อไปขอเข้าร่วม'
                      : 'โพสต์นี้อาจตั้งค่าเป็นส่วนตัวหรือเฉพาะเพื่อน',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final text = Mention.plain(r.text).trim();
    final isVideo = r.mediaType == 'video';
    final hasMedia = r.mediaUrl != null && r.mediaUrl!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(r, icon: r.sourcePrivate ? Icons.lock_outline : Icons.share),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: AuthorName(
                  uid: r.authorId,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        if (hasMedia)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Icon(
                  isVideo ? Icons.videocam_outlined : Icons.image_outlined,
                  size: 16,
                  color: Colors.black54,
                ),
                const SizedBox(width: 4),
                Text(
                  isVideo ? 'มีวิดีโอแนบ' : 'มีรูปภาพแนบ',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Text(
            'ดูโพสต์',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF0084FF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Resolved {
  final _Access access;
  final String? sourceName;
  final bool sourcePrivate;
  final String authorId;
  final String text;
  final String? mediaUrl;
  final String? mediaType;
  _Resolved(
    this.access, {
    this.sourceName,
    this.sourcePrivate = false,
    this.authorId = '',
    this.text = '',
    this.mediaUrl,
    this.mediaType,
  });
}
