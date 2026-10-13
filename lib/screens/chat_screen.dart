import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../utils/image_data.dart';
import 'home_feed_screen.dart' show AuthorName;

class ChatScreen extends StatefulWidget {
  final String peerUid;
  const ChatScreen({required this.peerUid, super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _maxImageBytes = 5 * 1024 * 1024;

  final _chat = ChatService();
  final _storage = StorageService();
  final _picker = ImagePicker();
  final _controller = TextEditingController();
  final _myUid = AuthService().currentUser?.uid ?? '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      _chat.messages(_myUid, widget.peerUid);
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    try {
      await _chat.send(fromUid: _myUid, toUid: widget.peerUid, text: text);
    } catch (e) {
      _toast('ส่งข้อความไม่สำเร็จ: $e');
    }
  }

  Future<void> _sendImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 480,
        maxHeight: 480,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        _toast('รูปใหญ่เกิน 5 MB');
        return;
      }
      setState(() => _sending = true);
      final url = await _storage.uploadChatImageBytes(bytes: bytes, uid: _myUid);
      await _chat.send(fromUid: _myUid, toUid: widget.peerUid, imageUrl: url);
    } catch (e) {
      _toast('ส่งรูปไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AuthorName(uid: widget.peerUid)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('โหลดแชทไม่สำเร็จ: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('ยังไม่มีข้อความ ทักทายได้เลย'));
                }
                return ListView.builder(
                  reverse: true, // ข้อความใหม่สุดอยู่ล่าง
                  padding: const EdgeInsets.all(10),
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _Bubble(
                    data: docs[i].data(),
                    mine: docs[i].data()['senderId'] == _myUid,
                  ),
                );
              },
            ),
          ),
          if (_sending) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _sending ? null : _sendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _sendText),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool mine;
  const _Bubble({required this.data, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = data['imageUrl'] as String?;
    final text = data['text'] as String?;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppImage(src: imageUrl, width: 220, fit: BoxFit.cover),
              )
            : Text(text ?? ''),
      ),
    );
  }
}
