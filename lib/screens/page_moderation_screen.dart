import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/page_service.dart';
import '../widgets/join_requests_section.dart';
import '../widgets/profile_link.dart';
import '../widgets/user_avatar.dart';

/// เครื่องมือผู้ดูแลเพจ (เหมือนชุมชน): อนุมัติคำขอ, ตั้ง/ถอดผู้ดูแล, นำออก, แบน/ยกเลิกแบน
/// เจ้าของทำได้ทุกอย่าง ผู้ดูแลทำได้เฉพาะคำขอเข้าร่วม และนำออก/แบนสมาชิกทั่วไป
class PageModerationScreen extends StatefulWidget {
  final String pageId;
  const PageModerationScreen({required this.pageId, super.key});

  @override
  State<PageModerationScreen> createState() => _PageModerationScreenState();
}

class _PageModerationScreenState extends State<PageModerationScreen> {
  final _service = PageService();
  final _uid = AuthService().currentUser?.uid ?? '';

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      _toast(success);
    } catch (e) {
      _toast(
        'ทำรายการไม่สำเร็จ: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<bool> _confirm(String title, String message, String okLabel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onMemberAction(
    String action,
    String memberId,
    bool isModerator,
  ) async {
    switch (action) {
      case 'mod':
        await _run(
          () => _service.setModerator(widget.pageId, memberId, !isModerator),
          isModerator ? 'ถอดผู้ดูแลแล้ว' : 'ตั้งเป็นผู้ดูแลแล้ว',
        );
      case 'kick':
        if (!await _confirm(
          'นำออกจากเพจ?',
          'สมาชิกจะถูกนำออกจากเพจ แต่ยังขอเข้าร่วมใหม่ได้',
          'นำออก',
        )) {
          return;
        }
        await _run(
          () => _service.removeMember(
            widget.pageId,
            memberId,
            targetIsModerator: isModerator,
          ),
          'นำออกจากเพจแล้ว',
        );
      case 'ban':
        if (!await _confirm(
          'นำออกและแบน?',
          'บัญชีนี้จะถูกนำออก และเข้าร่วม ดู หรือโพสต์ในเพจนี้ไม่ได้ จนกว่าจะยกเลิกแบน',
          'แบน',
        )) {
          return;
        }
        await _run(
          () => _service.removeMember(
            widget.pageId,
            memberId,
            ban: true,
            targetIsModerator: isModerator,
          ),
          'นำออกและแบนแล้ว',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เครื่องมือผู้ดูแลเพจ')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _service.page(widget.pageId),
        builder: (context, snap) {
          if (snap.hasError)
            return Center(child: Text('โหลดไม่สำเร็จ: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snap.data!.data();
          if (data == null) return const Center(child: Text('ไม่พบเพจนี้'));
          final ownerId = data['ownerId'] as String? ?? '';
          final moderators = List<String>.from(
            data['moderatorIds'] ?? const [],
          );
          if (!PageService.canModerate(data, _uid)) {
            return const Center(child: Text('ไม่มีสิทธิ์ดูหน้านี้'));
          }
          final isOwner = ownerId == _uid;
          final requests = List<String>.from(
            data['pendingRequests'] ?? const [],
          );
          final banned = List<String>.from(data['bannedIds'] ?? const []);
          final members = List<String>.from(data['memberIds'] ?? const [])
            ..sort((a, b) {
              int rank(String u) =>
                  u == ownerId ? 0 : (moderators.contains(u) ? 1 : 2);
              return rank(a).compareTo(rank(b));
            });

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              JoinRequestsSection(
                title: 'คำขอเข้าร่วม',
                kindLabel: 'เพจ',
                requests: requests.map((u) => JoinRequestItem(u)).toList(),
                onApprove: (u) =>
                    _service.approveRequest(widget.pageId, _uid, u),
                onDecline: (u) =>
                    _service.declineRequest(widget.pageId, _uid, u),
              ),
              _heading('สมาชิกและบทบาท'),
              ...members.map((memberId) {
                final isMod = moderators.contains(memberId);
                // ผู้ดูแลจัดการได้เฉพาะสมาชิกทั่วไป เจ้าของจัดการได้ทุกคนยกเว้นตัวเอง
                final canManage =
                    memberId != _uid &&
                    memberId != ownerId &&
                    (isOwner || !isMod);
                return ListTile(
                  leading: UserAvatar(uid: memberId, tappable: true),
                  title: ProfileLink(uid: memberId, child: _name(memberId)),
                  subtitle: Text(
                    memberId == ownerId
                        ? 'เจ้าของ'
                        : isMod
                        ? 'ผู้ดูแล'
                        : 'สมาชิก',
                  ),
                  trailing: !canManage
                      ? null
                      : PopupMenuButton<String>(
                          onSelected: (a) =>
                              _onMemberAction(a, memberId, isMod),
                          itemBuilder: (_) => [
                            if (isOwner)
                              PopupMenuItem(
                                value: 'mod',
                                child: Text(
                                  isMod ? 'ถอดผู้ดูแล' : 'ตั้งเป็นผู้ดูแล',
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'kick',
                              child: Text('นำออก'),
                            ),
                            const PopupMenuItem(
                              value: 'ban',
                              child: Text('นำออกและแบน'),
                            ),
                          ],
                        ),
                );
              }),
              _heading('บัญชีที่แบน'),
              if (banned.isEmpty)
                _empty('ไม่มีบัญชีที่แบน')
              else
                ...banned.map(
                  (u) => ListTile(
                    leading: UserAvatar(uid: u, tappable: true),
                    title: ProfileLink(uid: u, child: _name(u)),
                    trailing: TextButton(
                      onPressed: () => _run(
                        () => _service.unbanMember(widget.pageId, u),
                        'ยกเลิกแบนแล้ว',
                      ),
                      child: const Text('ยกเลิกแบน'),
                    ),
                  ),
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
