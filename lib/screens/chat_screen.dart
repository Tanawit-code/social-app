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
import 'home_feed_screen.dart' show AuthorName;

const _messengerBlue = Color(0xFF0084FF);
const _peerBubble = Color(0xFFF0F0F0);
const _fieldGrey = Color(0xFFF0F2F5);

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
  bool _hasText = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _readSubscription;

  @override
  void initState() {
    super.initState();
    final id = _chat.chatId(_myUid, widget.peerUid);
    _readSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(id)
        .collection('messages')
        .snapshots()
        .listen((_) {
          NotificationService().markChatRead(_myUid, id).catchError((_) {});
        });
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _readSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// มีข้อความ = ส่งข้อความ, ช่องว่าง = ส่งไลก์ 👍 (เหมือน Messenger)
  Future<void> _send() async {
    final typed = _controller.text.trim();
    final text = typed.isEmpty ? '👍' : typed;
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
      _toast('ส่งรูปไม่สำเร็จ: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        iconTheme: const IconThemeData(color: _messengerBlue),
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(uid: widget.peerUid, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: AuthorName(
                uid: widget.peerUid,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
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
                if (docs.isEmpty) return _EmptyChat(peerUid: widget.peerUid);
                return ListView.builder(
                  reverse: true, // ข้อความใหม่สุดอยู่ล่าง
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final sender = (d['senderId'] ?? '') as String;
                    final older = i + 1 < docs.length ? docs[i + 1].data() : null;
                    final newer = i > 0 ? docs[i - 1].data() : null;
                    // เรียงกลุ่มข้อความของคนเดียวกันติดกัน: first = เก่าสุดในกลุ่ม, last = ใหม่สุดในกลุ่ม
                    final first = older == null || older['senderId'] != sender;
                    final last = newer == null || newer['senderId'] != sender;
                    final ts = d['createdAt'] as Timestamp?;
                    final olderTs = older?['createdAt'] as Timestamp?;
                    final showTime =
                        ts != null &&
                        (olderTs == null ||
                            ts.toDate().difference(olderTs.toDate()).inMinutes >=
                                30);
                    return Column(
                      children: [
                        if (showTime) _TimeLabel(time: ts.toDate()),
                        _MessageRow(
                          data: d,
                          mine: sender == _myUid,
                          first: first,
                          last: last,
                          peerUid: widget.peerUid,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_sending)
            const LinearProgressIndicator(
              minHeight: 2,
              color: _messengerBlue,
              backgroundColor: Colors.transparent,
            ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'ส่งรูปภาพ',
                    icon: const Icon(Icons.image, color: _messengerBlue),
                    onPressed: _sending ? null : _sendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (_hasText) _send();
                      },
                      decoration: InputDecoration(
                        hintText: 'Aa',
                        filled: true,
                        fillColor: _fieldGrey,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _hasText ? Icons.send : Icons.thumb_up,
                      color: _messengerBlue,
                    ),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String peerUid;
  const _EmptyChat({required this.peerUid});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(uid: peerUid, radius: 40),
          const SizedBox(height: 12),
          AuthorName(
            uid: peerUid,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 4),
          const Text(
            'ส่งข้อความเพื่อเริ่มสนทนา',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

const _thaiMonths = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

class _TimeLabel extends StatelessWidget {
  final DateTime time;
  const _TimeLabel({required this.time});

  @override
  Widget build(BuildContext context) {
    final hm =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final today =
        time.year == now.year && time.month == now.month && time.day == now.day;
    final label = today ? hm : '${time.day} ${_thaiMonths[time.month - 1]} $hm';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.black45),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool mine;
  final bool first;
  final bool last;
  final String peerUid;

  const _MessageRow({
    required this.data,
    required this.mine,
    required this.first,
    required this.last,
    required this.peerUid,
  });

  void _openImage(BuildContext context, String src) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Center(child: AppImage(src: src, fit: BoxFit.contain)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'ปิด',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = data['imageUrl'] as String?;
    final text = (data['text'] ?? '') as String;
    final maxW = MediaQuery.of(context).size.width * 0.72;

    const big = Radius.circular(18);
    const small = Radius.circular(4);
    final radius = BorderRadius.only(
      topLeft: !mine && !first ? small : big,
      bottomLeft: !mine && !last ? small : big,
      topRight: mine && !first ? small : big,
      bottomRight: mine && !last ? small : big,
    );

    Widget content;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      content = GestureDetector(
        onTap: () => _openImage(context, imageUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AppImage(src: imageUrl, width: 220, fit: BoxFit.cover),
        ),
      );
    } else if (text == '👍') {
      content = const Text('👍', style: TextStyle(fontSize: 38));
    } else {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: mine ? _messengerBlue : _peerBubble,
          borderRadius: radius,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            color: mine ? Colors.white : Colors.black87,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: first ? 6 : 1.5),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            // เหมือน Messenger: โชว์รูปเฉพาะข้อความล่างสุดของกลุ่ม ที่เหลือเว้นที่ไว้
            SizedBox(
              width: 28,
              child: last ? UserAvatar(uid: peerUid, radius: 14) : null,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
