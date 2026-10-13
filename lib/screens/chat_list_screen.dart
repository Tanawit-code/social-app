import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import '../widgets/user_avatar.dart';
import 'home_feed_screen.dart' show AuthorName, formatRelativeTime;

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = AuthService().currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('แชท')),
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
                trailing: Text(
                  formatRelativeTime(d['lastAt'] as Timestamp?),
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
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
