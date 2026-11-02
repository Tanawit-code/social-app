import 'package:flutter/material.dart';
import '../screens/profile_screen.dart';

/// ครอบ widget ใดๆ (รูปโปรไฟล์ / ชื่อ) ให้กดแล้วเปิดโปรไฟล์ของ [uid]
class ProfileLink extends StatelessWidget {
  final String uid;
  final Widget child;
  const ProfileLink({required this.uid, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)),
      ),
      child: child,
    );
  }
}
