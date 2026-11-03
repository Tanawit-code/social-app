import 'package:flutter/material.dart';
import '../services/safety_service.dart';

/// ผลลัพธ์จาก dialog รายงาน
typedef ReportInput = ({String reason, String details});

/// dialog รายงานกลางของทั้งแอป: เลือกเหตุผลมาตรฐาน + รายละเอียดเพิ่มเติม
/// เลือก "อื่นๆ" ต้องกรอกรายละเอียด
Future<ReportInput?> showReportDialog(
  BuildContext context, {
  required String title,
}) => showDialog<ReportInput>(
  context: context,
  builder: (_) => _ReportDialog(title: title),
);

/// ขั้นตอนรายงานครบวงจร: dialog → ส่ง → แจ้งผล (รวมกรณีรายงานซ้ำ)
/// ส่งไปที่ reports/ ผ่าน [SafetyService] โดยค่าเริ่มต้น
/// ส่วนที่ต้องไปอยู่ที่อื่น (เช่นกล่องรายงานของชุมชน) ให้ส่ง [customSubmit]
Future<void> showReportFlow(
  BuildContext context, {
  required String title,
  String targetType = '',
  String targetId = '',
  String reportedUid = '',
  String contextId = '',
  Future<void> Function(String reason, String details)? customSubmit,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final input = await showReportDialog(context, title: title);
  if (input == null) return;
  try {
    if (customSubmit != null) {
      await customSubmit(input.reason, input.details);
    } else {
      await SafetyService().report(
        targetType: targetType,
        targetId: targetId,
        reason: input.reason,
        details: input.details,
        reportedUid: reportedUid,
        contextId: contextId,
      );
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('ส่งรายงานแล้ว ขอบคุณที่แจ้งให้ทราบ')),
    );
  } on AlreadyReportedException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('ส่งรายงานไม่สำเร็จ: $e')));
  }
}

class _ReportDialog extends StatefulWidget {
  final String title;
  const _ReportDialog({required this.title});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _reason != null &&
      (_reason != 'อื่นๆ' || _details.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('เลือกเหตุผลที่ต้องการรายงาน'),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(
              children: reportReasons
                  .map(
                    (r) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r),
                      value: r,
                    ),
                  )
                  .toList(),
            ),
          ),
          TextField(
            controller: _details,
            maxLength: 500,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _reason == 'อื่นๆ'
                  ? 'รายละเอียด (จำเป็น)'
                  : 'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
              border: const OutlineInputBorder(),
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
        onPressed: _canSend
            ? () => Navigator.pop(context, (
                reason: _reason!,
                details: _details.text.trim(),
              ))
            : null,
        child: const Text('ส่งรายงาน'),
      ),
    ],
  );
}
