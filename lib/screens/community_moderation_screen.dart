import '../widgets/profile_link.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/community_model.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../utils/time_ago.dart';
import '../widgets/join_requests_section.dart';
import 'home_feed_screen.dart' show AuthorName;
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
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: root
                    .collection('joinRequests')
                    .orderBy('createdAt')
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return _error(snap.error);
                  if (!snap.hasData) return const LinearProgressIndicator();
                  return JoinRequestsSection(
                    title: 'คำขอเข้าร่วม',
                    kindLabel: 'ชุมชน',
                    requests: snap.data!.docs
                        .map(
                          (d) => JoinRequestItem(
                            d.id,
                            d.data()['createdAt'] as Timestamp?,
                          ),
                        )
                        .toList(),
                    onApprove: (id) =>
                        service.approve(community, id, byUid: uid),
                    onDecline: (id) =>
                        service.decline(community, id, byUid: uid),
                  );
                },
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: root
                    .collection('reports')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _heading(count > 0 ? 'รายงาน ($count)' : 'รายงาน'),
                      if (snap.hasError)
                        _error(snap.error)
                      else if (!snap.hasData)
                        const LinearProgressIndicator()
                      else if (snap.data!.docs.isEmpty)
                        _empty('ไม่มีรายงานที่รอตรวจสอบ')
                      else
                        ...snap.data!.docs.map(
                          (report) => _ReportCard(
                            root: root,
                            community: community,
                            reportId: report.id,
                            data: report.data(),
                            service: service,
                          ),
                        ),
                    ],
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
                        leading: UserAvatar(uid: memberId, tappable: true),
                        title: ProfileLink(
                          uid: memberId,
                          child: _name(memberId),
                        ),
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
                            leading: UserAvatar(uid: doc.id, tappable: true),
                            title: ProfileLink(
                              uid: doc.id,
                              child: _name(doc.id),
                            ),
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

/// รายงานหนึ่งรายการสำหรับผู้ดูแลชุมชน: เห็นเนื้อหาที่ถูกรายงาน ผู้เขียน ผู้รายงาน เหตุผล
/// แล้วเลือกได้ว่า "ลบเนื้อหา" หรือ "ไม่พบปัญหา (ปิดรายงาน)"
class _ReportCard extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> root;
  final Community community;
  final String reportId;
  final Map<String, dynamic> data;
  final CommunityService service;
  const _ReportCard({
    required this.root,
    required this.community,
    required this.reportId,
    required this.data,
    required this.service,
  });

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _busy = false;
  late final Future<DocumentSnapshot<Map<String, dynamic>>> _target =
      _loadTarget();

  bool get _isComment => widget.data['commentId'] != null;

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadTarget() {
    final post = widget.root
        .collection('posts')
        .doc(widget.data['postId'] as String? ?? '_');
    return _isComment
        ? post
              .collection('comments')
              .doc(widget.data['commentId'] as String)
              .get()
        : post.get();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ทำรายการไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isComment ? 'ลบคอมเมนต์นี้?' : 'ลบโพสต์นี้?'),
        content: const Text('เนื้อหาจะถูกลบถาวรและปิดรายงานนี้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.service.removeReportedContent(
        widget.community.id,
        widget.reportId,
        widget.data,
      ),
      'ลบเนื้อหาและปิดรายงานแล้ว',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final scheme = Theme.of(context).colorScheme;
    final details = (d['details'] as String? ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    _isComment
                        ? Icons.comment_outlined
                        : Icons.article_outlined,
                    size: 16,
                  ),
                  label: Text(_isComment ? 'คอมเมนต์' : 'โพสต์'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d['reason'] as String? ?? 'รายงาน',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  timeAgo(d['createdAt'] as Timestamp?),
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ],
            ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(details),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Text('รายงานโดย ', style: TextStyle(color: scheme.outline)),
                  Flexible(
                    child: AuthorName(
                      uid: d['reporterId'] as String? ?? '',
                      tappable: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: _target,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const LinearProgressIndicator();
                  }
                  final t = snap.data?.data();
                  if (snap.hasError || t == null) {
                    return Text(
                      'ไม่พบเนื้อหานี้แล้ว (อาจถูกลบไปก่อนหน้า)',
                      style: TextStyle(color: scheme.outline),
                    );
                  }
                  final text = (t['text'] as String? ?? '').trim();
                  final hasMedia = t['mediaUrl'] != null;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'เขียนโดย ',
                            style: TextStyle(color: scheme.outline),
                          ),
                          Flexible(
                            child: AuthorName(
                              uid: t['authorId'] as String? ?? '',
                              tappable: true,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text.isEmpty
                            ? (hasMedia
                                  ? '[โพสต์มีรูป/วิดีโอ]'
                                  : '[ไม่มีข้อความ]')
                            : text,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.service.resolveReport(
                              widget.community.id,
                              widget.reportId,
                            ),
                            'ปิดรายงานแล้ว',
                          ),
                    child: const Text('ไม่พบปัญหา'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _busy ? null : _confirmRemove,
                    child: Text(_isComment ? 'ลบคอมเมนต์' : 'ลบโพสต์'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
