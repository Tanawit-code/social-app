import 'profile_link.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/image_data.dart';

/// วงกลมรูปโปรไฟล์จาก URL (ไม่มีรูป = ไอคอนคน)
class PhotoAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  const PhotoAvatar({this.url, this.radius = 20, super.key});

  @override
  Widget build(BuildContext context) {
    final provider = imageProviderFor(url);
    return CircleAvatar(
      radius: radius,
      backgroundImage: provider,
      onBackgroundImageError: provider != null ? (_, __) {} : null,
      child: provider == null ? Icon(Icons.person, size: radius * 0.9) : null,
    );
  }
}

/// รูปโปรไฟล์ของผู้ใช้ตาม uid — ฟัง users/{uid} แบบ real-time
/// จึงอัปเดตเองทันทีเมื่อเจ้าตัวเปลี่ยนรูป (ไม่ต้องรีเฟรชหน้า)
class UserAvatar extends StatefulWidget {
  final String uid;
  final double radius;

  /// true = กดรูปแล้วเปิดโปรไฟล์ของ uid นี้
  final bool tappable;
  const UserAvatar({
    required this.uid,
    this.radius = 20,
    this.tappable = false,
    super.key,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _open() {
    if (widget.uid.isEmpty) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _stream = _open();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _stream = _open();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar();
    return widget.tappable
        ? ProfileLink(uid: widget.uid, child: avatar)
        : avatar;
  }

  Widget _avatar() {
    final stream = _stream;
    if (stream == null) return PhotoAvatar(radius: widget.radius);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) => PhotoAvatar(
        url: snap.data?.data()?['photoUrl'] as String?,
        radius: widget.radius,
      ),
    );
  }
}
