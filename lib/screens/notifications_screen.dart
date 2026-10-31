import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/friend_service.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'home_feed_screen.dart' show AuthorName;
import 'privacy_settings_screen.dart';
import '../widgets/user_avatar.dart';

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

  @override
  void initState() {
    super.initState();
    // เปิดหน้านี้ = ถือว่าอ่านแล้ว (badge หายทันที)
    _service.markRead(_uid, messages: false);
  }

  String _action(String type) {
    switch (type) {
      case 'like':
        return 'ถูกใจโพสต์ของคุณ';
      case 'comment':
        return 'แสดงความคิดเห็นในโพสต์ของคุณ';
      case 'message':
        return 'ส่งข้อความถึงคุณ';
      case 'follow':
        return 'เริ่มติดตามคุณ';
      case 'follow_request':
        return 'ส่งคำขอติดตามบัญชีส่วนตัวของคุณ';
      case 'friend_accepted':
        return 'ตอบรับเป็นเพื่อนกับคุณ';
      default:
        return 'มีความเคลื่อนไหวใหม่';
    }
  }

  IconData _icon(String type) {
    switch (type) {
      case 'like':
        return Icons.thumb_up;
      case 'comment':
        return Icons.comment;
      case 'message':
        return Icons.chat_bubble;
      case 'follow':
        return Icons.person_add;
      case 'follow_request':
        return Icons.lock_open;
      case 'friend_accepted':
        return Icons.people;
      default:
        return Icons.notifications;
    }
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
          final docs = snap.data!.docs
              .where(
                (d) =>
                    !['message', 'friend_request'].contains(d.data()['type']),
              )
              .toList();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _friends.incoming(_uid),
            builder: (context, requestSnap) {
              if (requestSnap.hasError)
                return Center(
                  child: Text(
                    'โหลดคำขอเป็นเพื่อนไม่สำเร็จ: ${requestSnap.error}',
                  ),
                );
              if (!requestSnap.hasData)
                return const Center(child: CircularProgressIndicator());
              final requests = requestSnap.data!.docs;
              if (docs.isEmpty && requests.isEmpty) {
                return const Center(child: Text('ยังไม่มีการแจ้งเตือน'));
              }
              return ListView(
                children: [
                  if (requests.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'คำขอเป็นเพื่อน (${requests.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...requests.map((request) {
                      final sender = request.id;
                      return ListTile(
                        leading: UserAvatar(uid: sender),
                        title: AuthorName(uid: sender),
                        subtitle: const Text('ส่งคำขอเป็นเพื่อนถึงคุณ'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(uid: sender),
                          ),
                        ),
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            IconButton(
                              tooltip: 'ยอมรับ',
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              onPressed: () async {
                                try {
                                  await _friends.accept(
                                    receiver: _uid,
                                    sender: sender,
                                  );
                                } catch (error) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'ยอมรับคำขอไม่สำเร็จ: $error',
                                        ),
                                      ),
                                    );
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'ปฏิเสธ',
                              icon: const Icon(Icons.cancel_outlined),
                              onPressed: () async {
                                try {
                                  await _friends.decline(
                                    receiver: _uid,
                                    sender: sender,
                                  );
                                } catch (error) {
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'ปฏิเสธคำขอไม่สำเร็จ: $error',
                                        ),
                                      ),
                                    );
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 1),
                  ],
                  if (docs.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'การแจ้งเตือน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ...docs.map((doc) {
                    final d = doc.data();
                    final type = (d['type'] ?? '') as String;
                    final from = (d['fromUid'] ?? '') as String;
                    return ListTile(
                      leading: CircleAvatar(child: Icon(_icon(type))),
                      title: Row(
                        children: [
                          Flexible(child: AuthorName(uid: from)),
                          Text(' ${_action(type)}'),
                        ],
                      ),
                      subtitle: (d['text'] as String?) != null
                          ? Text(
                              d['text'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: type == 'follow_request'
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrivacySettingsScreen(),
                              ),
                            )
                          : type == 'message'
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(peerUid: from),
                              ),
                            )
                          : type == 'follow' || type == 'friend_accepted'
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileScreen(uid: from),
                              ),
                            )
                          : null,
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
