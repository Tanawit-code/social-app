import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../services/notification_service.dart';
import '../utils/image_data.dart';
import '../widgets/user_avatar.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  const GroupChatScreen({required this.groupId, super.key});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _text = TextEditingController();
  final _uid = AuthService().currentUser?.uid ?? '';
  bool _sending = false;
  bool _hasText = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _readSubscription;
  static const _colors = [0xFFF0F2F5, 0xFFE3F2FD, 0xFFFCE4EC, 0xFFE8F5E9, 0xFFFFF3E0, 0xFFEDE7F6, 0xFF263238];

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    _readSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.groupId)
        .collection('messages')
        .snapshots()
        .listen((_) {
          NotificationService()
              .markGroupRead(_uid, widget.groupId)
              .catchError((_) {});
        });
  }

  void _onTextChanged() {
    final hasText = _text.text.trim().isNotEmpty;
    if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
  }

  Future<void> _pickImage(Map<String, dynamic> group, String field) async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 55, maxWidth: 720, maxHeight: 720);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      final url = await StorageService().uploadChatImageBytes(bytes: bytes, uid: _uid);
      await ChatService().updateGroup(widget.groupId, _uid, {field: url});
    } catch (e) { if (mounted) _toast('อัปเดตรูปไม่สำเร็จ: $e'); }
  }

  Future<void> _settings(Map<String, dynamic> group) async {
    final owner = group['ownerId'] == _uid;
    if (!owner) {
      _showMembers(group);
      return;
    }
    final name = TextEditingController(text: group['name'] ?? '');
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (sheetContext) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ตั้งค่ากลุ่ม', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(sheetContext);
            _showMembers(group);
          },
          icon: const Icon(Icons.people_outline),
          label: Text('ดูสมาชิก (${((group['participants'] as List?) ?? []).length} คน)'),
        ),
        TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม', border: OutlineInputBorder()), onSubmitted: (_) async { if (name.text.trim().isNotEmpty) await ChatService().updateGroup(widget.groupId, _uid, {'name': name.text.trim()}); }),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [
          OutlinedButton.icon(onPressed: () async { await _pickImage(group, 'photoUrl'); if (context.mounted) Navigator.pop(sheetContext); }, icon: const Icon(Icons.photo_camera), label: const Text('เปลี่ยนรูปกลุ่ม')),
          OutlinedButton.icon(onPressed: () async { await _pickImage(group, 'backgroundUrl'); if (context.mounted) Navigator.pop(sheetContext); }, icon: const Icon(Icons.wallpaper), label: const Text('เลือกรูปพื้นหลัง')),
        ]),
        const SizedBox(height: 10), const Text('สีพื้นหลังแชท'), const SizedBox(height: 8),
        Wrap(spacing: 12, children: _colors.map((color) => InkWell(onTap: () async { await ChatService().updateGroup(widget.groupId, _uid, {'backgroundColor': color, 'backgroundUrl': ''}); if (context.mounted) Navigator.pop(sheetContext); }, child: CircleAvatar(radius: 19, backgroundColor: Color(color), child: (group['backgroundColor'] == color) ? const Icon(Icons.check, size: 18) : null))).toList()),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () async { if (name.text.trim().isEmpty) { _toast('กรุณาใส่ชื่อกลุ่ม'); return; } await ChatService().updateGroup(widget.groupId, _uid, {'name': name.text.trim()}); if (context.mounted) Navigator.pop(sheetContext); }, child: const Text('บันทึกชื่อ'))),
      ]),
    ))));
    name.dispose();
  }

  void _showMembers(Map<String, dynamic> group) {
    final memberIds = List<String>.from(group['participants'] ?? const []);
    final ownerId = group['ownerId'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Row(
                  children: [
                    const Icon(Icons.groups_outlined),
                    const SizedBox(width: 10),
                    Text('สมาชิก ${memberIds.length} คน', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').limit(200).snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) return Center(child: Text('โหลดสมาชิกไม่สำเร็จ: ${snap.error}'));
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final members = snap.data!.docs.where((user) => memberIds.contains(user.id)).toList()
                      ..sort((a, b) {
                        if (a.id == ownerId) return -1;
                        if (b.id == ownerId) return 1;
                        return ((a.data()['name'] ?? '') as String).compareTo((b.data()['name'] ?? '') as String);
                      });
                    return ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final name = (member.data()['name'] ?? '') as String;
                        final photo = member.data()['photoUrl'] as String? ?? '';
                        return ListTile(
                          leading: CircleAvatar(backgroundImage: imageProviderFor(photo), child: photo.isEmpty ? Text(name.isEmpty ? '?' : name.characters.first) : null),
                          title: Text(name.isEmpty ? 'สมาชิก' : name),
                          trailing: member.id == ownerId ? const Chip(label: Text('เจ้าของ')) : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }

  Future<void> _send() async {
    if (_sending) return;
    final typed = _text.text.trim();
    final value = typed.isEmpty ? '\u{1F44D}' : typed;
    _text.clear(); setState(() => _sending = true);
    try { await ChatService().sendGroup(groupId: widget.groupId, fromUid: _uid, text: value); }
    catch (e) { _toast('ส่งข้อความไม่สำเร็จ: $e'); }
    finally { if (mounted) setState(() => _sending = false); }
  }

  Future<void> _sendImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 55, maxWidth: 720, maxHeight: 720);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final url = await StorageService().uploadChatImageBytes(bytes: bytes, uid: _uid);
      await ChatService().sendGroup(groupId: widget.groupId, fromUid: _uid, imageUrl: url);
    } catch (e) { _toast('ส่งรูปไม่สำเร็จ: $e'); }
  }

  @override
  void dispose() { _readSubscription?.cancel(); _text.removeListener(_onTextChanged); _text.dispose(); super.dispose(); }

  String _timeLabel(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('chats').doc(widget.groupId).snapshots(),
    builder: (context, groupSnap) {
      if (!groupSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      final group = groupSnap.data!.data() ?? {};
      final bgUrl = group['backgroundUrl'] as String? ?? '';
      final bgColor = Color((group['backgroundColor'] as num?)?.toInt() ?? 0xFFF0F2F5);
      final photo = group['photoUrl'] as String? ?? '';
      return Scaffold(appBar: AppBar(title: Row(children: [CircleAvatar(radius: 18, backgroundImage: imageProviderFor(photo), child: photo.isEmpty ? const Icon(Icons.groups, size: 18) : null), const SizedBox(width: 10), Expanded(child: Text(group['name'] ?? 'กลุ่ม', maxLines: 1, overflow: TextOverflow.ellipsis))]), actions: [IconButton(tooltip: 'ตั้งค่ากลุ่ม', icon: const Icon(Icons.more_vert), onPressed: () => _settings(group))]),
        body: DecoratedBox(decoration: BoxDecoration(color: bgColor, image: bgUrl.isEmpty ? null : DecorationImage(image: imageProviderFor(bgUrl)!, fit: BoxFit.cover, opacity: 0.35)), child: Column(children: [
          Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('chats').doc(widget.groupId).collection('messages').orderBy('createdAt', descending: true).limit(100).snapshots(), builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('โหลดข้อความไม่สำเร็จ: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (snap.data!.docs.isEmpty) return const Center(child: Text('เริ่มบทสนทนาของกลุ่ม'));
            return ListView.builder(reverse: true, padding: const EdgeInsets.all(12), itemCount: snap.data!.docs.length, itemBuilder: (context, i) {
              final msg = snap.data!.docs[i].data();
              final mine = msg['senderId'] == _uid;
              final sender = (msg['senderId'] ?? '') as String;
              final image = msg['imageUrl'] as String?;
              final text = (msg['text'] ?? '') as String;
              final time = _timeLabel(msg['createdAt'] as Timestamp?);
              final isLike = text == '\u{1F44D}';
              final content = image != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(17), child: AppImage(src: image, width: 220, height: 180))
                  : isLike
                      ? const Text('\u{1F44D}', style: TextStyle(fontSize: 38))
                      : Text(text, style: TextStyle(color: mine ? Colors.white : Colors.black87, fontSize: 15));
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!mine) ...[UserAvatar(uid: sender, radius: 14), const SizedBox(width: 6)],
                    Flexible(
                      child: Column(
                        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (!mine) AuthorNameInline(uid: sender),
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: image == null && !isLike ? const EdgeInsets.symmetric(horizontal: 13, vertical: 9) : EdgeInsets.zero,
                            decoration: isLike || image != null ? null : BoxDecoration(color: mine ? const Color(0xFF0084FF) : Colors.white, borderRadius: BorderRadius.circular(17)),
                            child: content,
                          ),
                          if (time.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3, left: 8, right: 8),
                              child: Text(time, style: const TextStyle(fontSize: 10, color: Colors.black45)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            });
          })),
          SafeArea(top: false, child: Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(6, 6, 6, 6), child: Row(children: [IconButton(tooltip: 'ส่งรูป', onPressed: _sending ? null : _sendImage, icon: const Icon(Icons.image, color: Color(0xFF0084FF))), Expanded(child: TextField(controller: _text, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: 'ข้อความถึงกลุ่ม', filled: true, fillColor: const Color(0xFFF0F2F5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)))), IconButton(tooltip: _hasText ? 'ส่งข้อความ' : 'กดไลค์', onPressed: _sending ? null : _send, icon: Icon(_hasText ? Icons.send : Icons.thumb_up, color: const Color(0xFF0084FF)))]))),
        ])));
    },
  );
}

class AuthorNameInline extends StatelessWidget {
  final String uid;
  const AuthorNameInline({required this.uid, super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(), builder: (context, snap) => Padding(padding: const EdgeInsets.only(left: 8, bottom: 2), child: Text(snap.data?.data()?['name'] ?? 'สมาชิก', style: const TextStyle(fontSize: 11, color: Colors.black54))));
}
