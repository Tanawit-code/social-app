import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/community_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/friend_service.dart';
import '../utils/time_ago.dart';
import 'chat_screen.dart';
import 'community_detail_screen.dart';
import 'community_moderation_screen.dart';
import 'page_detail_screen.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';
import 'home_feed_screen.dart' show AuthorName;
import 'privacy_settings_screen.dart';
import 'admin_reports_screen.dart';
import '../widgets/user_avatar.dart';

/// หมวดสำหรับตัวกรองด้านบนของหน้า
enum _Filter { all, post, people, community, page }

class _SourceStyle {
  final String label;
  final IconData icon;
  final Color color;
  const _SourceStyle(this.label, this.icon, this.color);
}

const _styles = <String, _SourceStyle>{
  NotifSource.post: _SourceStyle(
    'โพสต์',
    Icons.article_outlined,
    Color(0xFF1E88E5),
  ),
  NotifSource.friend: _SourceStyle(
    'เพื่อน',
    Icons.people_outline,
    Color(0xFF43A047),
  ),
  NotifSource.follow: _SourceStyle(
    'ผู้ติดตาม',
    Icons.person_add_alt,
    Color(0xFF8E24AA),
  ),
  NotifSource.chat: _SourceStyle(
    'แชท',
    Icons.chat_bubble_outline,
    Color(0xFF00897B),
  ),
  NotifSource.community: _SourceStyle(
    'ชุมชน',
    Icons.groups_outlined,
    Color(0xFFF4511E),
  ),
  NotifSource.page: _SourceStyle('เพจ', Icons.flag_outlined, Color(0xFFD81B60)),
  NotifSource.moderation: _SourceStyle(
    'การดูแลระบบ',
    Icons.shield_outlined,
    Color(0xFFEF6C00),
  ),
};

/// แจ้งเตือนจากระบบดูแลโพสต์ (ไม่มีผู้ส่ง — fromUid = 'system')
const _moderationTypes = [
  NotifType.adminReport,
  NotifType.postHidden,
  NotifType.postRestored,
  NotifType.postEditRejected,
];

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
  final _friends = FriendService();
  final _uid = AuthService().currentUser?.uid ?? '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = _service
      .stream(_uid);
  _Filter _filter = _Filter.all;

  /// id ของแจ้งเตือนที่ "ยังไม่อ่าน" ตอนเปิดหน้า — ใช้ไฮไลต์แม้ badge จะถูกเคลียร์แล้ว
  final Set<String> _unreadIds = {};

  String _action(String type) {
    switch (type) {
      case NotifType.like:
        return 'ถูกใจโพสต์ของคุณ';
      case NotifType.comment:
        return 'แสดงความคิดเห็นในโพสต์ของคุณ';
      case NotifType.mentionPost:
        return 'แท็กคุณในโพสต์';
      case NotifType.mentionComment:
        return 'แท็กคุณในความคิดเห็น';
      case NotifType.message:
        return 'ส่งข้อความถึงคุณ';
      case NotifType.follow:
        return 'เริ่มติดตามคุณ';
      case NotifType.followRequest:
        return 'ส่งคำขอติดตามบัญชีส่วนตัวของคุณ';
      case NotifType.friendAccepted:
        return 'ตอบรับเป็นเพื่อนกับคุณ';
      case NotifType.communityJoinRequest:
        return 'ขอเข้าร่วมชุมชนของคุณ';
      case NotifType.communityJoinApproved:
        return 'อนุมัติให้คุณเข้าร่วมชุมชนแล้ว';
      case NotifType.communityJoinDeclined:
        return 'ปฏิเสธคำขอเข้าร่วมชุมชนของคุณ';
      case NotifType.pageJoinRequest:
        return 'ขอเข้าร่วมเพจของคุณ';
      case NotifType.pageJoinApproved:
        return 'อนุมัติให้คุณเข้าร่วมเพจแล้ว';
      case NotifType.pageJoinDeclined:
        return 'ปฏิเสธคำขอเข้าร่วมเพจของคุณ';
      case NotifType.adminReport:
        return 'มีรายงานใหม่รอตรวจสอบ';
      case NotifType.postHidden:
        return 'โพสต์ของคุณถูกซ่อน';
      case NotifType.postRestored:
        return 'โพสต์ของคุณกลับมาแสดงแล้ว';
      case NotifType.postEditRejected:
        return 'การแก้ไขโพสต์ยังไม่เพียงพอ';
      default:
        return 'มีความเคลื่อนไหวใหม่';
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case NotifType.like:
        return Icons.thumb_up;
      case NotifType.comment:
        return Icons.comment;
      case NotifType.mentionPost:
      case NotifType.mentionComment:
        return Icons.alternate_email;
      case NotifType.message:
        return Icons.chat_bubble;
      case NotifType.follow:
        return Icons.person_add;
      case NotifType.followRequest:
        return Icons.lock_open;
      case NotifType.friendAccepted:
        return Icons.people;
      case NotifType.communityJoinRequest:
      case NotifType.pageJoinRequest:
        return Icons.how_to_reg;
      case NotifType.communityJoinApproved:
      case NotifType.pageJoinApproved:
        return Icons.check_circle;
      case NotifType.communityJoinDeclined:
      case NotifType.pageJoinDeclined:
        return Icons.cancel;
      case NotifType.adminReport:
        return Icons.flag;
      case NotifType.postHidden:
        return Icons.visibility_off;
      case NotifType.postRestored:
        return Icons.visibility;
      case NotifType.postEditRejected:
        return Icons.edit_off;
      default:
        return Icons.notifications;
    }
  }

  bool _inFilter(String source) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.post:
        return source == NotifSource.post;
      case _Filter.people:
        return source == NotifSource.friend || source == NotifSource.follow;
      case _Filter.community:
        return source == NotifSource.community;
      case _Filter.page:
        return source == NotifSource.page;
    }
  }

  void _trackUnread(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final fresh = docs
        .where((d) => d.data()['isRead'] != true && !_unreadIds.contains(d.id))
        .map((d) => d.id)
        .toList();
    if (fresh.isEmpty) return;
    _unreadIds.addAll(fresh);
    // เปิดหน้านี้ = ถือว่าอ่านแล้ว (badge หายทันที) แต่ยังไฮไลต์แถวที่เพิ่งมา
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.markRead(_uid, messages: false).catchError((_) {});
    });
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _openCommunity(String id, {required bool moderate}) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('communities')
          .doc(id)
          .get();
      if (!snap.exists) {
        _toast('ไม่พบชุมชนนี้แล้ว');
        return;
      }
      final community = Community.fromDoc(snap);
      if (!mounted) return;
      _push(
        moderate
            ? CommunityModerationScreen(community: community)
            : CommunityDetailScreen(community: community),
      );
    } catch (e) {
      _toast('เปิดชุมชนไม่สำเร็จ: $e');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// แตะแจ้งเตือน → ไปยังต้นทางของมัน
  void _open(Map<String, dynamic> d) {
    final type = (d['type'] ?? '') as String;
    final from = (d['fromUid'] ?? '') as String;
    final source = (d['source'] ?? NotifSource.fromType(type)) as String;
    final sourceId = (d['sourceId'] ?? '') as String;
    // แจ้งเตือนที่ผูกกับโพสต์ (แท็ก/ถูกใจ/คอมเมนต์) → เปิดโพสต์นั้นโดยตรง
    final postId = (d['postId'] ?? '') as String;
    if (type == NotifType.adminReport) {
      _push(const AdminReportsScreen());
      return;
    }
    const postTypes = [
      NotifType.mentionPost,
      NotifType.mentionComment,
      NotifType.like,
      NotifType.comment,
      NotifType.postHidden,
      NotifType.postRestored,
      NotifType.postEditRejected,
    ];
    if (postId.isNotEmpty && postTypes.contains(type)) {
      final openComments =
          type == NotifType.mentionComment || type == NotifType.comment;
      if (source == NotifSource.community && sourceId.isNotEmpty) {
        _push(
          CommunityPostScreen(
            communityId: sourceId,
            postId: postId,
            openComments: openComments,
          ),
        );
      } else {
        _push(PostDetailScreen(postId: postId, openComments: openComments));
      }
      return;
    }
    switch (source) {
      case NotifSource.community:
        if (sourceId.isNotEmpty) {
          _openCommunity(
            sourceId,
            moderate: type == NotifType.communityJoinRequest,
          );
        }
        return;
      case NotifSource.page:
        if (sourceId.isNotEmpty) _push(PageDetailScreen(pageId: sourceId));
        return;
      case NotifSource.chat:
        _push(ChatScreen(peerUid: from));
        return;
    }
    if (type == NotifType.followRequest) {
      _push(const PrivacySettingsScreen());
    } else if (type == NotifType.follow || type == NotifType.friendAccepted) {
      _push(ProfileScreen(uid: from));
    }
  }

  bool _tappable(Map<String, dynamic> d) {
    final type = (d['type'] ?? '') as String;
    final source = (d['source'] ?? NotifSource.fromType(type)) as String;
    final postId = (d['postId'] ?? '') as String;
    if (postId.isNotEmpty &&
        [
          NotifType.mentionPost,
          NotifType.mentionComment,
          NotifType.like,
          NotifType.comment,
          NotifType.postHidden,
          NotifType.postRestored,
          NotifType.postEditRejected,
        ].contains(type)) {
      return true;
    }
    if (type == NotifType.adminReport) return true;
    return source != NotifSource.post;
  }

  Widget _filterBar() {
    const labels = {
      _Filter.all: 'ทั้งหมด',
      _Filter.post: 'โพสต์',
      _Filter.people: 'เพื่อนและผู้ติดตาม',
      _Filter.community: 'ชุมชน',
      _Filter.page: 'เพจ',
    };
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: _Filter.values
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(labels[f]!),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _sourceTag(String source, String? name) {
    final style = _styles[source] ?? _styles[NotifSource.post]!;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              name == null || name.isEmpty
                  ? style.label
                  : '${style.label} · $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: style.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final type = (d['type'] ?? '') as String;
    final from = (d['fromUid'] ?? '') as String;
    final source = (d['source'] ?? NotifSource.fromType(type)) as String;
    final style = _styles[source] ?? _styles[NotifSource.post]!;
    final text = d['text'] as String?;
    final unread = _unreadIds.contains(doc.id);
    final isSystem = _moderationTypes.contains(type) || from == 'system';
    return Material(
      color: unread
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.07)
          : Colors.transparent,
      child: ListTile(
        isThreeLine: true,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            if (isSystem)
              CircleAvatar(
                radius: 22,
                backgroundColor: style.color.withValues(alpha: 0.15),
                child: Icon(Icons.shield, color: style.color),
              )
            else
              UserAvatar(uid: from, radius: 22),
            Positioned(
              right: -4,
              bottom: -4,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: style.color,
                child: Icon(_icon(type), size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        title: isSystem
            ? Text(
                _action(type),
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AuthorName(
                    uid: from,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(' ${_action(type)}'),
                ],
              ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sourceTag(source, d['sourceName'] as String?),
            if (text != null && text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  text,
                  maxLines: isSystem ? 4 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                timeAgo(d['createdAt'] as Timestamp?),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
        trailing: unread
            ? const Icon(Icons.circle, size: 10, color: Color(0xFF1E88E5))
            : null,
        onTap: _tappable(d) ? () => _open(d) : null,
      ),
    );
  }

  Widget _friendRequests(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> requests,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'คำขอเป็นเพื่อน (${requests.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        ...requests.map((request) {
          final sender = request.id;
          return ListTile(
            leading: UserAvatar(uid: sender),
            title: AuthorName(uid: sender),
            subtitle: const Text('ส่งคำขอเป็นเพื่อนถึงคุณ'),
            onTap: () => _push(ProfileScreen(uid: sender)),
            trailing: Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: 'ยอมรับ',
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () async {
                    try {
                      await _friends.accept(receiver: _uid, sender: sender);
                    } catch (error) {
                      _toast('ยอมรับคำขอไม่สำเร็จ: $error');
                    }
                  },
                ),
                IconButton(
                  tooltip: 'ปฏิเสธ',
                  icon: const Icon(Icons.cancel_outlined),
                  onPressed: () async {
                    try {
                      await _friends.decline(receiver: _uid, sender: sender);
                    } catch (error) {
                      _toast('ปฏิเสธคำขอไม่สำเร็จ: $error');
                    }
                  },
                ),
              ],
            ),
          );
        }),
        const Divider(height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การแจ้งเตือน')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('โหลดไม่สำเร็จ: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // ข้อความแชทไปแสดงที่ไอคอนแชทแล้ว หน้านี้เหลือเฉพาะอย่างอื่น
          final all = snap.data!.docs
              .where(
                (d) =>
                    !['message', 'friend_request'].contains(d.data()['type']),
              )
              .toList();
          _trackUnread(all);
          final docs = all.where((d) {
            final type = (d.data()['type'] ?? '') as String;
            final source =
                (d.data()['source'] ?? NotifSource.fromType(type)) as String;
            return _inFilter(source);
          }).toList();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _friends.incoming(_uid),
            builder: (context, requestSnap) {
              if (requestSnap.hasError) {
                return Center(
                  child: Text(
                    'โหลดคำขอเป็นเพื่อนไม่สำเร็จ: ${requestSnap.error}',
                  ),
                );
              }
              if (!requestSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final showRequests =
                  _filter == _Filter.all || _filter == _Filter.people;
              final requests = showRequests
                  ? requestSnap.data!.docs
                  : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              return Column(
                children: [
                  _filterBar(),
                  Expanded(
                    child: docs.isEmpty && requests.isEmpty
                        ? const Center(child: Text('ยังไม่มีการแจ้งเตือน'))
                        : ListView(
                            children: [
                              if (requests.isNotEmpty)
                                _friendRequests(requests),
                              ...docs.map(_tile),
                            ],
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
