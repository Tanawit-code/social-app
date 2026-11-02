import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// ไอคอนบอกสถานะโพสต์ — public = สาธารณะ, friends = เพื่อน, private = ส่วนตัว
/// [scope] ใช้ต่อท้ายคำอธิบาย เช่น 'เพจ' / 'ชุมชน' (เพจส่วนตัว, ชุมชนสาธารณะ)
class PrivacyIcon extends StatelessWidget {
  final String privacy;
  final String scope;
  final double size;
  final Color color;
  const PrivacyIcon(
    this.privacy, {
    this.scope = '',
    this.size = 14,
    this.color = Colors.black54,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (privacy) {
      'private' => (Icons.lock_outline, 'ส่วนตัว'),
      'friends' => (Icons.people_outline, 'เพื่อน'),
      _ => (Icons.public, 'สาธารณะ'),
    };
    return Tooltip(
      message: '$scope$label',
      child: Icon(icon, size: size, color: color),
    );
  }
}

/// ไอคอนสถานะของโพสต์ในคอลเลกชัน posts
/// โพสต์ในเพจใช้ความเป็นส่วนตัวของเพจ ส่วนโพสต์ปกติใช้ audience ของโพสต์
class PostPrivacyIcon extends StatelessWidget {
  final String audience;
  final String? pageId;
  final double size;
  final Color color;
  const PostPrivacyIcon({
    required this.audience,
    this.pageId,
    this.size = 14,
    this.color = Colors.black54,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final id = pageId;
    if (id == null) {
      return PrivacyIcon(audience, size: size, color: color);
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('pages')
          .doc(id)
          .snapshots(),
      builder: (context, snap) => PrivacyIcon(
        snap.data?.data()?['privacy'] == 'private' ? 'private' : 'public',
        scope: 'เพจ',
        size: size,
        color: color,
      ),
    );
  }
}
