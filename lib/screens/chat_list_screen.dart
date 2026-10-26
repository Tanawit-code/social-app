import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import '../widgets/user_avatar.dart';
import 'home_feed_screen.dart' show AuthorName, formatRelativeTime;
import 'group_chat_screen.dart';
import 'create_group_screen.dart';
import '../utils/image_data.dart';
import '../services/notification_service.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = AuthService().currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('แชท'), actions: [IconButton(tooltip: 'สร้างกลุ่ม', icon: const Icon(Icons.group_add), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())))]),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ChatService().chats(me),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('โหลดไม่สำเร็จ: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs.toList()
            ..sort((a, b) {
              final ta = a.data()['lastAt'] as Timestamp?;
              final tb = b.data()['lastAt'] as Timestamp?;
              return (tb?.millisecondsSinceEpoch ?? 0)
                  .compareTo(ta?.millisecondsSinceEpoch ?? 0);
            });
          if (docs.isEmpty) {
            return const Center(
              child: Text('ยังไม่มีแชท — ค้นหาผู้ใช้แล้วกดเพื่อเริ่มคุย'),
            );
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = docs[i].data();
              if (d['type'] == 'group') {
                final photo = d['photoUrl'] as String? ?? '';
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: CircleAvatar(radius: 26, backgroundImage: imageProviderFor(photo), child: photo.isEmpty ? const Icon(Icons.groups) : null),
                  title: Text(d['name'] ?? 'กลุ่ม', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text(d['lastMessage'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: StreamBuilder<int>(
                    stream: NotificationService().groupUnreadCount(me, docs[i].id),
                    builder: (context, unread) => Row(mainAxisSize: MainAxisSize.min, children: [
                      if ((unread.data ?? 0) > 0) ...[
                        CircleAvatar(radius: 11, backgroundColor: const Color(0xFFE53935), child: Text((unread.data! > 99 ? '99+' : '${unread.data}'), style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                      ],
                      Text(formatRelativeTime(d['lastAt'] as Timestamp?), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    ]),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupChatScreen(groupId: docs[i].id))),
                );
              }
              final peer = (d['participants'] as List)
                  .cast<String>()
                  .firstWhere((u) => u != me, orElse: () => '');
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: UserAvatar(uid: peer, radius: 26),
                title: AuthorName(
                  uid: peer,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                trailing: StreamBuilder<int>(
                  stream: NotificationService().chatUnreadCount(me, docs[i].id),
                  builder: (context, unread) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((unread.data ?? 0) > 0) ...[
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: const Color(0xFFE53935),
                          child: Text(
                            unread.data! > 99 ? '99+' : '${unread.data}',
                            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        formatRelativeTime(d['lastAt'] as Timestamp?),
                        style: const TextStyle(fontSize: 11, color: Colors.black45),
                      ),
                    ],
                  ),
                ),
                subtitle: Text(
                  d['lastMessage'] ?? '',
                  style: const TextStyle(color: Colors.black54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatScreen(peerUid: peer)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
