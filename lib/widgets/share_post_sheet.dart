import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../utils/image_data.dart';
import 'user_avatar.dart';
import '../screens/home_feed_screen.dart' show AuthorName;

/// เปิดหน้าต่างเลือกแชท/กลุ่มเพื่อส่งโพสต์ — [postRef] สร้างด้วย [ChatService.postRef]
/// ส่งเฉพาะ "ลิงก์โพสต์" ผู้รับจะเห็นเนื้อหาได้ตามสิทธิ์ของตัวเอง
/// (โพสต์ในชุมชน/เพจส่วนตัว ผู้รับที่ไม่ใช่สมาชิกต้องขอเข้าร่วมก่อน)
Future<void> showSharePostToChat(
  BuildContext context, {
  required Map<String, dynamic> postRef,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _SharePostSheet(postRef: postRef),
  );
}

class _SharePostSheet extends StatefulWidget {
  final Map<String, dynamic> postRef;
  const _SharePostSheet({required this.postRef});

  @override
  State<_SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<_SharePostSheet> {
  final _chat = ChatService();
  final _me = AuthService().currentUser?.uid ?? '';
  final _message = TextEditingController();
  // คีย์: 'g:<groupId>' = กลุ่มแชท, 'u:<uid>' = แชทส่วนตัวกับผู้ใช้
  final _selected = <String>{};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream = _chat
      .chats(_me);
  late final Future<List<DocumentSnapshot<Map<String, dynamic>>>> _friends =
      _chat.mutualFriends(_me).catchError(
        (_) => <DocumentSnapshot<Map<String, dynamic>>>[],
      );
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  Future<void> _send() async {
    if (_sending || _selected.isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final caption = _message.text.trim();
    var ok = 0;
    var failed = 0;
    for (final key in _selected) {
      final id = key.substring(2);
      try {
        if (key.startsWith('g:')) {
          await _chat.sendGroup(
            groupId: id,
            fromUid: _me,
            text: caption.isEmpty ? null : caption,
            sharedPost: widget.postRef,
          );
        } else {
          await _chat.send(
            fromUid: _me,
            toUid: id,
            text: caption.isEmpty ? null : caption,
            sharedPost: widget.postRef,
          );
        }
        ok++;
      } catch (_) {
        failed++;
      }
    }
    nav.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'ส่งโพสต์แล้ว ($ok แชท)'
              : ok == 0
              ? 'ส่งโพสต์ไม่สำเร็จ'
              : 'ส่งโพสต์แล้ว $ok แชท, ไม่สำเร็จ $failed แชท',
        ),
      ),
    );
  }

  Widget _tile({
    required String keyId,
    required Widget leading,
    required Widget title,
    String? subtitle,
  }) {
    final checked = _selected.contains(keyId);
    return CheckboxListTile(
      value: checked,
      onChanged: _sending ? null : (_) => _toggle(keyId),
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: leading,
      title: title,
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      dense: true,
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.black54,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ส่งโพสต์ไปยังแชท / กลุ่ม',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _message,
                maxLength: 500,
                minLines: 1,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'เขียนข้อความถึงผู้รับ (ไม่บังคับ)',
                  counterText: '',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _chatsStream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text('โหลดรายการแชทไม่สำเร็จ: ${snap.error}'),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs.toList()
                    ..sort((a, b) {
                      final ta = a.data()['lastAt'] as Timestamp?;
                      final tb = b.data()['lastAt'] as Timestamp?;
                      return (tb?.millisecondsSinceEpoch ?? 0).compareTo(
                        ta?.millisecondsSinceEpoch ?? 0,
                      );
                    });
                  final peersWithChat = <String>{};
                  final groups = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  final directs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  for (final d in docs) {
                    final data = d.data();
                    if (data['type'] == 'group') {
                      groups.add(d);
                    } else {
                      final parts = List<String>.from(
                        data['participants'] ?? const [],
                      );
                      final peer = parts.firstWhere(
                        (u) => u != _me,
                        orElse: () => '',
                      );
                      if (peer.isEmpty) continue;
                      peersWithChat.add(peer);
                      directs.add(d);
                    }
                  }
                  return ListView(
                    children: [
                      if (groups.isNotEmpty) _sectionLabel('กลุ่มแชท'),
                      for (final d in groups)
                        _tile(
                          keyId: 'g:${d.id}',
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundImage: imageProviderFor(
                              d.data()['photoUrl'] as String? ?? '',
                            ),
                            child: (d.data()['photoUrl'] as String? ?? '')
                                    .isEmpty
                                ? const Icon(Icons.groups)
                                : null,
                          ),
                          title: Text(
                            d.data()['name'] as String? ?? 'กลุ่ม',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (directs.isNotEmpty) _sectionLabel('แชทส่วนตัว'),
                      for (final d in directs)
                        Builder(
                          builder: (_) {
                            final parts = List<String>.from(
                              d.data()['participants'] ?? const [],
                            );
                            final peer = parts.firstWhere((u) => u != _me);
                            return _tile(
                              keyId: 'u:$peer',
                              leading: UserAvatar(uid: peer, radius: 20),
                              title: AuthorName(uid: peer),
                            );
                          },
                        ),
                      FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
                        future: _friends,
                        builder: (context, friendSnap) {
                          final others = (friendSnap.data ?? const [])
                              .where((f) => !peersWithChat.contains(f.id))
                              .toList();
                          if (others.isEmpty) return const SizedBox.shrink();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionLabel('เพื่อน'),
                              for (final f in others)
                                _tile(
                                  keyId: 'u:${f.id}',
                                  leading: UserAvatar(uid: f.id, radius: 20),
                                  title: AuthorName(uid: f.id),
                                ),
                            ],
                          );
                        },
                      ),
                      if (groups.isEmpty && directs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'ยังไม่มีแชทหรือกลุ่ม — เริ่มคุยกับเพื่อนก่อนแล้วกลับมาส่งโพสต์ได้เลย',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selected.isEmpty || _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      _selected.isEmpty ? 'เลือกแชทหรือกลุ่ม' : 'ส่ง (${_selected.length})',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
