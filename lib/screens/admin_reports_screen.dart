import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/community_model.dart';
import '../models/event_model.dart';
import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import '../utils/time_ago.dart';
import 'community_detail_screen.dart';
import 'event_detail_screen.dart';
import 'home_feed_screen.dart' show AuthorName;
import 'page_detail_screen.dart';
import 'profile_screen.dart';

const _statusLabels = {
  'open': 'รอตรวจ',
  'reviewing': 'กำลังตรวจ',
  'resolved': 'ดำเนินการแล้ว',
  'dismissed': 'ไม่พบปัญหา',
};

const _statusColors = {
  'open': Color(0xFFE53935),
  'reviewing': Color(0xFFFB8C00),
  'resolved': Color(0xFF43A047),
  'dismissed': Color(0xFF757575),
};

const _typeLabels = {
  'post': 'โพสต์',
  'community_post': 'โพสต์ในชุมชน',
  'profile': 'โปรไฟล์',
  'comment': 'ความคิดเห็น',
  'message': 'ข้อความแชท',
  'group_message': 'ข้อความกลุ่ม',
  'page': 'เพจ',
  'community': 'ชุมชน',
  'event': 'กิจกรรม',
};

/// หน้าแอดมิน: ดูรายงานทั้งหมดจาก reports/ แล้วเปลี่ยนสถานะ
/// (เข้าได้เฉพาะผู้ที่มี custom claim admin — ตั้งด้วย tools/set_admin.mjs)
/// รายงานเก่าที่ไม่มีฟิลด์ status ถือว่า "รอตรวจ"
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final _db = FirebaseFirestore.instance;
  // กรองฝั่งแอป เพื่อไม่ต้องสร้าง composite index เพิ่ม
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = _db
      .collection('reports')
      .orderBy('createdAt', descending: true)
      .limit(300)
      .snapshots();
  String _filter = 'open'; // หรือ 'all'
  final _moderation = ModerationService();
  // จำนวนผู้รายงานต่อโพสต์ (คำนวณใหม่ทุกครั้งที่ stream อัปเดต) key = ชนิด:รหัสโพสต์
  Map<String, int> _perTarget = {};

  String _targetKey(Map<String, dynamic> d) =>
      '${d['targetType']}:${d['contextId'] ?? ''}:${d['targetId']}';

  /// ซ่อนโพสต์: เลือกจำนวนวัน (หรือจนกว่าเจ้าของจะแก้ไข) + เหตุผลที่จะแจ้งเจ้าของโพสต์
  Future<void> _hidePost(Map<String, dynamic> d) async {
    final input = await showDialog<({int days, String note})>(
      context: context,
      builder: (_) => const _HideDialog(),
    );
    if (input == null) return;
    try {
      await _moderation.hidePost(
        postId: d['targetId'] as String,
        communityId: d['targetType'] == 'community_post'
            ? d['contextId'] as String?
            : null,
        days: input.days,
        note: input.note,
      );
      _toast('ซ่อนโพสต์แล้ว และแจ้งเจ้าของโพสต์แล้ว');
    } catch (e) {
      _toast('ซ่อนโพสต์ไม่สำเร็จ: $e');
    }
  }

  Future<void> _unhidePost(Map<String, dynamic> d) async {
    try {
      await _moderation.unhidePost(
        postId: d['targetId'] as String,
        communityId: d['targetType'] == 'community_post'
            ? d['contextId'] as String?
            : null,
      );
      _toast('เลิกซ่อนโพสต์แล้ว และแจ้งเจ้าของโพสต์แล้ว');
    } catch (e) {
      _toast('เลิกซ่อนไม่สำเร็จ: $e');
    }
  }

  String _status(Map<String, dynamic> d) => (d['status'] as String?) ?? 'open';

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await _db.collection('reports').doc(id).update({
        'status': status,
        'reviewedBy': AuthService().currentUser?.uid ?? '',
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _toast('เปลี่ยนสถานะไม่สำเร็จ: $e');
    }
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _openTarget(Map<String, dynamic> d) async {
    final type = d['targetType'] as String? ?? '';
    final id = d['targetId'] as String? ?? '';
    try {
      switch (type) {
        case 'profile':
          _push(ProfileScreen(uid: id));
        case 'page':
          _push(PageDetailScreen(pageId: id));
        case 'community':
          final snap = await _db.collection('communities').doc(id).get();
          if (!snap.exists) {
            _toast('ไม่พบชุมชนนี้แล้ว');
            return;
          }
          _push(CommunityDetailScreen(community: Community.fromDoc(snap)));
        case 'event':
          final snap = await _db.collection('events').doc(id).get();
          if (!snap.exists) {
            _toast('ไม่พบกิจกรรมนี้แล้ว');
            return;
          }
          _push(EventDetailScreen(event: SocialEvent.fromDoc(snap)));
        default:
          await Clipboard.setData(ClipboardData(text: id));
          _toast('คัดลอก ID แล้ว — ใช้ค้นหาใน Firebase Console');
      }
    } catch (e) {
      _toast('เปิดไม่สำเร็จ: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('รายงานทั้งหมด (แอดมิน)')),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'โหลดรายงานไม่สำเร็จ (ต้องเป็นแอดมิน): ${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data!.docs;
        // นับจำนวนครั้งที่แต่ละบัญชีถูกรายงาน (เฉพาะที่โหลดมา) เพื่อช่วยจัดลำดับ
        final perUser = <String, int>{};
        for (final r in all) {
          final u = r.data()['reportedUid'] as String? ?? '';
          if (u.isNotEmpty) perUser[u] = (perUser[u] ?? 0) + 1;
        }
        final perTarget = <String, Set<String>>{};
        for (final r in all) {
          final x = r.data();
          if (_status(x) == 'open' || _status(x) == 'reviewing') {
            (perTarget[_targetKey(x)] ??= {}).add(x['reporterId'] as String? ?? '');
          }
        }
        _perTarget = {for (final e in perTarget.entries) e.key: e.value.length};
        final counts = <String, int>{};
        for (final r in all) {
          counts[_status(r.data())] = (counts[_status(r.data())] ?? 0) + 1;
        }
        final shown = all
            .where((r) => _filter == 'all' || _status(r.data()) == _filter)
            .toList();
        return Column(
          children: [
            SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                children: [
                  for (final f in [
                    'open',
                    'reviewing',
                    'resolved',
                    'dismissed',
                    'all',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          f == 'all'
                              ? 'ทั้งหมด (${all.length})'
                              : '${_statusLabels[f]} (${counts[f] ?? 0})',
                        ),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('ไม่มีรายงานในหมวดนี้'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: shown.length,
                      itemBuilder: (context, i) => _card(shown[i], perUser),
                    ),
            ),
          ],
        );
      },
    ),
  );

  Widget _card(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, int> perUser,
  ) {
    final d = doc.data();
    final status = _status(d);
    final type = d['targetType'] as String? ?? '';
    final reported = d['reportedUid'] as String? ?? '';
    final details = (d['details'] as String? ?? '').trim();
    final color = _statusColors[status] ?? Colors.grey;
    final canOpen = ['profile', 'page', 'community', 'event'].contains(type);
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
                  label: Text(_typeLabels[type] ?? type),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    d['reason'] as String? ?? 'รายงาน',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _statusLabels[status] ?? status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(details),
              ),
            const SizedBox(height: 8),
            _line('รายงานโดย', d['reporterId'] as String? ?? ''),
            if (reported.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(child: _line('เจ้าของเนื้อหา', reported)),
                  if ((perUser[reported] ?? 0) > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        'ถูกรายงาน ${perUser[reported]} ครั้ง',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE53935),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                timeAgo(d['createdAt'] as Timestamp?),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            if (type == 'post' || type == 'community_post') ...[
              if ((_perTarget[_targetKey(d)] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'โพสต์นี้ถูกรายงานโดย ${_perTarget[_targetKey(d)]} คน (ซ่อนอัตโนมัติเมื่อถึง 3 คน)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE53935),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _hidePost(d),
                    icon: const Icon(Icons.visibility_off, size: 18),
                    label: const Text('ซ่อนโพสต์'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _unhidePost(d),
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('เลิกซ่อน'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => _openTarget(d),
                  icon: Icon(
                    canOpen ? Icons.open_in_new : Icons.copy,
                    size: 18,
                  ),
                  label: Text(canOpen ? 'เปิดดู' : 'คัดลอก ID'),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'เปลี่ยนสถานะ',
                  onSelected: (v) => _setStatus(doc.id, v),
                  itemBuilder: (_) => [
                    for (final e in _statusLabels.entries)
                      if (e.key != status)
                        PopupMenuItem(
                          value: e.key,
                          child: Text(
                            e.key == 'open'
                                ? 'เปิดใหม่'
                                : 'ตั้งเป็น "${e.value}"',
                          ),
                        ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Text('เปลี่ยนสถานะ'),
                        Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String uid) => Row(
    children: [
      Text(
        '$label ',
        style: const TextStyle(color: Colors.black54, fontSize: 13),
      ),
      Flexible(
        child: AuthorName(
          uid: uid,
          tappable: true,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    ],
  );
}


/// ตัวเลือกการซ่อนโพสต์: กี่วัน + เหตุผล (เหตุผลจะแสดงให้เจ้าของโพสต์เห็นในแจ้งเตือน)
class _HideDialog extends StatefulWidget {
  const _HideDialog();

  @override
  State<_HideDialog> createState() => _HideDialogState();
}

class _HideDialogState extends State<_HideDialog> {
  static const _options = <(int, String)>[
    (1, '1 วัน'),
    (3, '3 วัน'),
    (7, '7 วัน'),
    (14, '14 วัน'),
    (30, '30 วัน'),
    (0, 'จนกว่าเจ้าของจะแก้ไข'),
  ];
  int _days = 7;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ซ่อนโพสต์'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ซ่อนนานแค่ไหน'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final o in _options)
                ChoiceChip(
                  label: Text(o.$2),
                  selected: _days == o.$1,
                  onSelected: (_) => setState(() => _days = o.$1),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'ถ้าเจ้าของแก้ไขเนื้อหาจริงระหว่างที่ซ่อน ระบบจะตรวจและแสดงโพสต์อีกครั้งก่อนครบกำหนด',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 200,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'เหตุผล (แจ้งให้เจ้าของโพสต์ทราบ)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (days: _days, note: _note.text.trim())),
        child: const Text('ซ่อนโพสต์'),
      ),
    ],
  );
}
