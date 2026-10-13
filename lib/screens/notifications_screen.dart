import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';
import 'home_feed_screen.dart' show AuthorName;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService();
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
              .where((d) => d.data()['type'] != 'message')
              .toList();
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีการแจ้งเตือน'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = docs[i].data();
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
                onTap: type == 'message'
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(peerUid: from),
                        ),
                      )
                    : type == 'follow'
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(uid: from),
                        ),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
