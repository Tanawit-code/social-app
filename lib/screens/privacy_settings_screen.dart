import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../widgets/user_avatar.dart';
import 'profile_screen.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _db = FirebaseFirestore.instance;
  final _follows = FollowService();
  final _uid = AuthService().currentUser?.uid ?? '';
  bool _saving = false;

  Future<void> _setPrivate(bool value) async {
    setState(() => _saving = true);
    try {
      await _db.collection('users').doc(_uid).update({'isPrivate': value});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _respond(String requester, {required bool accept}) async {
    try {
      if (accept) {
        await _follows.acceptRequest(owner: _uid, requester: requester);
      } else {
        await _follows.declineRequest(owner: _uid, requester: requester);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ดำเนินการไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ความเป็นส่วนตัว')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').doc(_uid).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData)
          return const Center(child: CircularProgressIndicator());
        final isPrivate = userSnap.data!.data()?['isPrivate'] == true;
        return ListView(
          children: [
            SwitchListTile.adaptive(
              value: isPrivate,
              onChanged: _saving ? null : _setPrivate,
              secondary: Icon(isPrivate ? Icons.lock_outline : Icons.public),
              title: const Text('บัญชีส่วนตัว'),
              subtitle: Text(
                isPrivate
                    ? 'คนที่ยังไม่ได้รับอนุมัติจะเห็นข้อมูลโปรไฟล์พื้นฐาน แต่ดูโพสต์ไม่ได้ ผู้ติดตามใหม่ต้องได้รับอนุมัติ'
                    : 'ทุกคนดูโพสต์สาธารณะและติดตามได้โดยไม่ต้องรออนุมัติ',
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text(
                'คำขอติดตาม',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'อนุมัติแล้วจึงจะเห็นโพสต์ที่จำกัดไว้สำหรับผู้ติดตาม',
              ),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _follows.requests(_uid),
              builder: (context, requestSnap) {
                if (requestSnap.hasError)
                  return const ListTile(title: Text('โหลดคำขอไม่สำเร็จ'));
                if (!requestSnap.hasData)
                  return const Center(child: CircularProgressIndicator());
                final requests = requestSnap.data!.docs;
                if (requests.isEmpty)
                  return const ListTile(title: Text('ไม่มีคำขอติดตามค้างอยู่'));
                return Column(
                  children: requests.map((request) {
                    final requester = request.id;
                    return FutureBuilder<
                      DocumentSnapshot<Map<String, dynamic>>
                    >(
                      future: _db.collection('users').doc(requester).get(),
                      builder: (context, personSnap) {
                        final person =
                            personSnap.data?.data() ??
                            const <String, dynamic>{};
                        final name = person['name'] as String? ?? 'ผู้ใช้';
                        final photo = person['photoUrl'] as String? ?? '';
                        return ListTile(
                          leading: PhotoAvatar(url: photo, radius: 22),
                          title: Text(name),
                          subtitle: const Text('ขอติดตามบัญชีของคุณ'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(uid: requester),
                            ),
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'ปฏิเสธ',
                                onPressed: () =>
                                    _respond(requester, accept: false),
                                icon: const Icon(Icons.close),
                              ),
                              IconButton(
                                tooltip: 'อนุมัติ',
                                onPressed: () =>
                                    _respond(requester, accept: true),
                                icon: const Icon(Icons.check_circle_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('การมองเห็นโพสต์'),
              subtitle: Text(
                'ตั้งผู้ชมของแต่ละโพสต์เป็นสาธารณะ เพื่อน หรือส่วนตัวได้ตอนสร้าง/แก้ไขโพสต์ การตั้งบัญชีส่วนตัวจะป้องกันคนที่ไม่ได้รับอนุมัติจากการดูโพสต์ในโปรไฟล์',
              ),
            ),
          ],
        );
      },
    ),
  );
}
