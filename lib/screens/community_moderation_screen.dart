import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/community_model.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../widgets/user_avatar.dart';

class CommunityModerationScreen extends StatelessWidget {
  final Community community;
  const CommunityModerationScreen({required this.community, super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService().currentUser?.uid ?? '';
    final root = FirebaseFirestore.instance
        .collection('communities')
        .doc(community.id);
    final service = CommunityService();
    return Scaffold(
      appBar: AppBar(title: const Text('เครื่องมือกลั่นกรอง')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: root.collection('members').doc(uid).snapshots(),
        builder: (context, roleSnap) {
          final role = roleSnap.data?.data()?['role'];
          if (!roleSnap.hasData)
            return const Center(child: CircularProgressIndicator());
          if (role != 'owner' && role != 'moderator')
            return const Center(child: Text('ไม่มีสิทธิ์ดูหน้านี้'));
          final isOwner = role == 'owner';
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _heading('คำขอเข้าร่วม'),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: root
                    .collection('joinRequests')
                    .orderBy('createdAt')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return _error(snap.error);
                  if (!snap.hasData) return const LinearProgressIndicator();
                  if (snap.data!.docs.isEmpty)
                    return _empty('ไม่มีคำขอค้างอยู่');
                  return Column(
                    children: snap.data!.docs
                        .map(
                          (request) => ListTile(
                            leading: UserAvatar(uid: request.id),
                            title: _name(request.id),
                            subtitle: const Text('ขอเข้าร่วมชุมชน'),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: 'ปฏิเสธ',
                                  onPressed: () =>
                                      service.decline(community.id, request.id),
                                  icon: const Icon(Icons.close),
                                ),
                                IconButton(
                                  tooltip: 'อนุมัติ',
                                  onPressed: () =>
                                      service.approve(community.id, request.id),
                                  icon: const Icon(Icons.check_circle_outline),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              _heading('รายงานโพสต์'),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: root
                    .collection('reports')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return _error(snap.error);
                  if (!snap.hasData) return const LinearProgressIndicator();
                  if (snap.data!.docs.isEmpty) return _empty('ไม่มีรายงาน');
                  return Column(
                    children: snap.data!.docs.map((report) {
                      final data = report.data();
                      return ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(data['reason'] as String? ?? 'รายงานโพสต์'),
                        subtitle: Text('Post ID: ${data['postId'] ?? ''}'),
                        trailing: IconButton(
                          tooltip: 'ปิดรายงาน',
                          onPressed: () =>
                              service.resolveReport(community.id, report.id),
                          icon: const Icon(Icons.done),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              _heading('สมาชิกและบทบาท'),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: root
                    .collection('members')
                    .orderBy('joinedAt')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return _error(snap.error);
                  if (!snap.hasData) return const LinearProgressIndicator();
                  return Column(
                    children: snap.data!.docs.map((member) {
                      final memberId = member.id;
                      final memberRole =
                          member.data()['role'] as String? ?? 'member';
                      return ListTile(
                        leading: UserAvatar(uid: memberId),
                        title: _name(memberId),
                        subtitle: Text(
                          memberRole == 'owner'
                              ? 'เจ้าของ'
                              : memberRole == 'moderator'
                              ? 'ผู้ดูแล'
                              : 'สมาชิก',
                        ),
                        trailing: memberId == uid || memberRole == 'owner'
                            ? null
                            : PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'ban')
                                    service.banMember(community.id, memberId);
                                  if (action == 'mod' && isOwner)
                                    service.setModerator(
                                      community.id,
                                      memberId,
                                      memberRole != 'moderator',
                                    );
                                },
                                itemBuilder: (_) => [
                                  if (isOwner)
                                    PopupMenuItem(
                                      value: 'mod',
                                      child: Text(
                                        memberRole == 'moderator'
                                            ? 'ถอดผู้ดูแล'
                                            : 'ตั้งเป็นผู้ดูแล',
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'ban',
                                    child: Text('นำออกและแบน'),
                                  ),
                                ],
                              ),
                      );
                    }).toList(),
                  );
                },
              ),
              _heading('บัญชีที่แบน'),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: root.collection('banned').snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return _error(snap.error);
                  if (!snap.hasData) return const LinearProgressIndicator();
                  if (snap.data!.docs.isEmpty)
                    return _empty('ไม่มีบัญชีที่แบน');
                  return Column(
                    children: snap.data!.docs
                        .map(
                          (doc) => ListTile(
                            leading: UserAvatar(uid: doc.id),
                            title: _name(doc.id),
                            trailing: TextButton(
                              onPressed: () =>
                                  service.unbanMember(community.id, doc.id),
                              child: const Text('ยกเลิกแบน'),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
    ),
  );
  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(text, style: const TextStyle(color: Colors.black54)),
  );
  Widget _error(Object? error) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      'โหลดข้อมูลไม่สำเร็จ: $error',
      style: const TextStyle(color: Colors.red),
    ),
  );
  Widget _name(String uid) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) =>
            Text(snap.data?.data()?['name'] as String? ?? 'สมาชิก'),
      );
}
