import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../screens/home_feed_screen.dart' show AuthorName;
import '../utils/time_ago.dart';
import 'user_avatar.dart';

/// คำขอเข้าร่วมหนึ่งรายการ (ใช้ร่วมกันทั้งชุมชนและเพจ)
class JoinRequestItem {
  final String uid;

  /// เวลาที่ขอ — เพจเก็บเป็นรายการ uid จึงไม่มีเวลา (ใส่ null ได้)
  final Timestamp? requestedAt;
  const JoinRequestItem(this.uid, [this.requestedAt]);
}

/// ส่วน "คำขอเข้าร่วม" แบบมืออาชีพ: หัวข้อ + จำนวน, ว่างแล้วมี empty state,
/// แต่ละแถวมีรูป/ชื่อ/เวลา และปุ่ม ปฏิเสธ / อนุมัติ พร้อมสถานะกำลังทำงาน
/// ปฏิเสธต้องยืนยันก่อน และมีปุ่ม "อนุมัติทั้งหมด" เมื่อมีหลายคำขอ
class JoinRequestsSection extends StatefulWidget {
  final String title;
  final String kindLabel; // 'ชุมชน' หรือ 'เพจ'
  final List<JoinRequestItem> requests;
  final Future<void> Function(String uid) onApprove;
  final Future<void> Function(String uid) onDecline;
  const JoinRequestsSection({
    required this.title,
    required this.kindLabel,
    required this.requests,
    required this.onApprove,
    required this.onDecline,
    super.key,
  });

  @override
  State<JoinRequestsSection> createState() => _JoinRequestsSectionState();
}

class _JoinRequestsSectionState extends State<JoinRequestsSection> {
  final Set<String> _busy = {};
  bool _bulk = false;

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<bool> _run(String uid, Future<void> Function(String) action) async {
    setState(() => _busy.add(uid));
    try {
      await action(uid);
      return true;
    } catch (e) {
      _toast('ทำรายการไม่สำเร็จ: ${_clean(e)}');
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(uid));
    }
  }

  Future<void> _approve(String uid) async {
    if (await _run(uid, widget.onApprove)) _toast('อนุมัติเข้าร่วมแล้ว');
  }

  Future<void> _decline(String uid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ปฏิเสธคำขอ?'),
        content: Text(
          'ผู้ใช้จะได้รับแจ้งว่าคำขอเข้าร่วม${widget.kindLabel}ถูกปฏิเสธ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ปฏิเสธ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (await _run(uid, widget.onDecline)) _toast('ปฏิเสธคำขอแล้ว');
  }

  Future<void> _approveAll() async {
    setState(() => _bulk = true);
    var done = 0;
    for (final r in List<JoinRequestItem>.from(widget.requests)) {
      try {
        await widget.onApprove(r.uid);
        done++;
      } catch (_) {}
    }
    if (mounted) setState(() => _bulk = false);
    _toast('อนุมัติแล้ว $done จาก ${widget.requests.length} คำขอ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final requests = widget.requests;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.how_to_reg_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (requests.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${requests.length}',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Spacer(),
                if (requests.length > 1)
                  TextButton(
                    onPressed: _bulk ? null : _approveAll,
                    child: Text(_bulk ? 'กำลังอนุมัติ…' : 'อนุมัติทั้งหมด'),
                  ),
              ],
            ),
            if (requests.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 36,
                        color: scheme.outline,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'ไม่มีคำขอที่รออนุมัติ',
                        style: TextStyle(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...requests.map((r) {
                final busy = _busy.contains(r.uid) || _bulk;
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          UserAvatar(uid: r.uid, radius: 22, tappable: true),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AuthorName(
                                  uid: r.uid,
                                  tappable: true,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  r.requestedAt == null
                                      ? 'ขอเข้าร่วม${widget.kindLabel}'
                                      : 'ขอเข้าร่วม · ${timeAgo(r.requestedAt)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: busy ? null : () => _decline(r.uid),
                              child: const Text('ปฏิเสธ'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: busy ? null : () => _approve(r.uid),
                              child: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('อนุมัติ'),
                            ),
                          ),
                        ],
                      ),
                      if (r != requests.last) const Divider(height: 20),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
