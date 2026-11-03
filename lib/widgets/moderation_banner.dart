import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// ใช้กับโพสต์ในชุมชนที่เก็บเป็น Map (โพสต์หน้าแรกใช้ [Post.isHiddenNow] / [Post.isHiddenFor])
bool moderationHiddenNow(Map<String, dynamic> data) {
  if (data['hidden'] != true) return false;
  final until = data['hiddenUntil'];
  if (until is! Timestamp) return true; // ไม่มีกำหนด = ซ่อนจนกว่าจะแก้ไข
  return until.toDate().isAfter(DateTime.now());
}

bool moderationHiddenFor(Map<String, dynamic> data, String viewerUid) =>
    moderationHiddenNow(data) && data['authorId'] != viewerUid;

/// แถบแจ้งเจ้าของโพสต์ว่าโพสต์ถูกซ่อน พร้อมปุ่มแก้ไข
/// (โพสต์ที่ถูกซ่อนจะกลับมาแสดงเมื่อแก้ไขจริง ระบบตรวจให้อัตโนมัติ และแจ้งผลทางแจ้งเตือน)
class HiddenPostBanner extends StatelessWidget {
  final String? hiddenBy; // 'reports' | 'admin'
  final String? reason;
  final Timestamp? until;
  final bool editRejected;
  final VoidCallback? onEdit;

  const HiddenPostBanner({
    this.hiddenBy,
    this.reason,
    this.until,
    this.editRejected = false,
    this.onEdit,
    super.key,
  });

  /// สร้างจากข้อมูลดิบของเอกสารโพสต์ (ใช้กับโพสต์ชุมชน)
  factory HiddenPostBanner.fromData(
    Map<String, dynamic> data, {
    VoidCallback? onEdit,
  }) => HiddenPostBanner(
    hiddenBy: data['hiddenBy'] as String?,
    reason: data['hiddenReason'] as String?,
    until: data['hiddenUntil'] as Timestamp?,
    editRejected: data['editRejectedAt'] != null,
    onEdit: onEdit,
  );

  String _untilText() {
    final d = until?.toDate();
    if (d == null) return 'จนกว่าคุณจะแก้ไขโพสต์';
    return 'ถึงวันที่ ${d.day}/${d.month}/${d.year + 543}';
  }

  @override
  Widget build(BuildContext context) {
    final byAdmin = hiddenBy == 'admin';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_off, size: 18, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'โพสต์นี้ถูกซ่อน (${_untilText()})',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            byAdmin
                ? 'แอดมินซ่อนโพสต์นี้${reason == null || reason!.isEmpty ? '' : ' เหตุผล: $reason'}'
                : 'โพสต์ถูกรายงานจากผู้ใช้หลายคน ระบบจึงซ่อนไว้ชั่วคราว',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 2),
          const Text(
            'คนอื่นมองไม่เห็นโพสต์นี้ — แก้ไขเนื้อหาให้เหมาะสม ระบบจะตรวจว่าแก้ไขจริงแล้วแสดงโพสต์อีกครั้ง',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          if (editRejected)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'การแก้ไขครั้งล่าสุดยังไม่เพียงพอ ลองปรับเนื้อหาเพิ่มเติม',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          if (onEdit != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('แก้ไขโพสต์'),
              ),
            ),
        ],
      ),
    );
  }
}
