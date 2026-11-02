import 'package:flutter/material.dart';
import '../widgets/user_avatar.dart';
import 'home_feed_screen.dart' show AuthorName;

/// สมาชิกหนึ่งคนในรายชื่อ (ใช้ร่วมกันทั้งเพจและชุมชน)
class MemberEntry {
  final String uid;

  /// 'owner' | 'moderator' | 'member'
  final String role;
  const MemberEntry(this.uid, [this.role = 'member']);
}

/// หน้ารายชื่อสมาชิก — กดที่ชื่อหรือรูปเพื่อเปิดโปรไฟล์
class MembersListScreen extends StatelessWidget {
  final String title;
  final Stream<List<MemberEntry>> members;
  const MembersListScreen({
    required this.title,
    required this.members,
    super.key,
  });

  static int _rank(String role) => switch (role) {
    'owner' => 0,
    'moderator' => 1,
    _ => 2,
  };

  static String? _roleLabel(String role) => switch (role) {
    'owner' => 'เจ้าของ',
    'moderator' => 'ผู้ดูแล',
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: StreamBuilder<List<MemberEntry>>(
      stream: members,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('โหลดรายชื่อสมาชิกไม่สำเร็จ: ${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!.toList()
          ..sort((a, b) => _rank(a.role).compareTo(_rank(b.role)));
        if (list.isEmpty) return const Center(child: Text('ยังไม่มีสมาชิก'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            final label = _roleLabel(m.role);
            return ListTile(
              leading: UserAvatar(uid: m.uid, tappable: true),
              title: AuthorName(uid: m.uid, tappable: true),
              trailing: label == null ? null : Chip(label: Text(label)),
            );
          },
        );
      },
    ),
  );
}
