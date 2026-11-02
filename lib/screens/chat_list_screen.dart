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
import '../widgets/chat_actions.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  // สร้าง stream ครั้งเดียว (เดิมสร้างใหม่ทุกครั้งที่ rebuild ทำให้สมัครฟังซ้ำ)
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _statesStream =
      ChatService().chatStates(AuthService().currentUser?.uid ?? '');
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream =
      ChatService().chats(AuthService().currentUser?.uid ?? '');

  @override
  Widget build(BuildContext context) {
    final me = AuthService().currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('แชท'),
        actions: [
          IconButton(
            tooltip: 'สร้างกลุ่ม',
            icon: const Icon(Icons.group_add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _statesStream,
        builder: (context, statesSnap) {
          // สถานะ "ลบแชท/ลบประวัติ" รายห้อง (อ่านไม่ได้ก็ถือว่าไม่มี)
          final stateDocs =
              statesSnap.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final states = <String, Map<String, dynamic>>{
            for (final d in stateDocs) d.id: d.data(),
          };
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _chatsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('โหลดไม่สำเร็จ: ${snap.error}'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs =
                  snap.data!.docs
                      .where(
                        (d) => !ChatService.isHidden(states[d.id], d.data()),
                      )
                      .toList()
                    ..sort((a, b) {
                      final ta = a.data()['lastAt'] as Timestamp?;
                      final tb = b.data()['lastAt'] as Timestamp?;
                      return (tb?.millisecondsSinceEpoch ?? 0).compareTo(
                        ta?.millisecondsSinceEpoch ?? 0,
                      );
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
                      key: ValueKey(docs[i].id),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundImage: imageProviderFor(photo),
                        child: photo.isEmpty ? const Icon(Icons.groups) : null,
                      ),
                      title: Text(
                        d['name'] ?? 'กลุ่ม',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        ChatService.previewFor(states[docs[i].id], d),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: StreamBuilder<int>(
                        stream: NotificationService().groupUnreadCount(
                          me,
                          docs[i].id,
                        ),
                        builder: (context, unread) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if ((unread.data ?? 0) > 0) ...[
                              CircleAvatar(
                                radius: 11,
                                backgroundColor: const Color(0xFFE53935),
                                child: Text(
                                  (unread.data! > 99
                                      ? '99+'
                                      : '${unread.data}'),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              formatRelativeTime(d['lastAt'] as Timestamp?),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                            IconButton(
                              tooltip: 'ตัวเลือกแชท',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.more_vert, size: 20),
                              onPressed: () => showChatActions(
                                context: context,
                                me: me,
                                chatId: docs[i].id,
                                title: d['name'] ?? 'กลุ่ม',
                                isGroup: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      onLongPress: () => showChatActions(
                        context: context,
                        me: me,
                        chatId: docs[i].id,
                        title: d['name'] ?? 'กลุ่ม',
                        isGroup: true,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupChatScreen(groupId: docs[i].id),
                        ),
                      ),
                    );
                  }
                  final peer = (d['participants'] as List)
                      .cast<String>()
                      .firstWhere((u) => u != me, orElse: () => '');
                  return ListTile(
                    key: ValueKey(docs[i].id),
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
                      stream: NotificationService().chatUnreadCount(
                        me,
                        docs[i].id,
                      ),
                      builder: (context, unread) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if ((unread.data ?? 0) > 0) ...[
                            CircleAvatar(
                              radius: 11,
                              backgroundColor: const Color(0xFFE53935),
                              child: Text(
                                unread.data! > 99 ? '99+' : '${unread.data}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            formatRelativeTime(d['lastAt'] as Timestamp?),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black45,
                            ),
                          ),
                          IconButton(
                            tooltip: 'ตัวเลือกแชท',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.more_vert, size: 20),
                            onPressed: () => showChatActions(
                              context: context,
                              me: me,
                              chatId: docs[i].id,
                              title: 'ตัวเลือกแชท',
                            ),
                          ),
                        ],
                      ),
                    ),
                    subtitle: Text(
                      ChatService.previewFor(states[docs[i].id], d),
                      style: const TextStyle(color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onLongPress: () => showChatActions(
                      context: context,
                      me: me,
                      chatId: docs[i].id,
                      title: 'ตัวเลือกแชท',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(peerUid: peer),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
