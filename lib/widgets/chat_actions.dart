import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';

/// เมนู 2 ทางเลือกที่แยกกัน (ทำเฉพาะฝั่งของเรา คนอื่นยังเห็นแชทตามเดิม)
///  - ลบประวัติแชท : ล้างข้อความเก่าทั้งหมด แต่ห้องแชทยังอยู่ในรายการ
///  - ลบแชท        : นำห้องแชทออกจากรายการ (ข้อความใหม่จะทำให้ห้องกลับมา
///                   และเห็นเฉพาะข้อความตั้งแต่หลังลบ)
Future<void> showChatActions({
  required BuildContext context,
  required String me,
  required String chatId,
  required String title,
  bool isGroup = false,
  bool leaveScreenOnDelete = false,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('ลบประวัติแชท'),
            subtitle: const Text(
              'ล้างข้อความเก่า แต่ยังเก็บห้องแชทไว้ในรายการ',
            ),
            onTap: () => Navigator.pop(ctx, 'clear'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('ลบแชท', style: TextStyle(color: Colors.red)),
            subtitle: const Text('นำห้องแชทออกจากรายการของคุณ'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'clear') {
    await confirmClearHistory(context, me: me, chatId: chatId);
  } else {
    await confirmDeleteChat(
      context,
      me: me,
      chatId: chatId,
      isGroup: isGroup,
      leaveScreenOnDelete: leaveScreenOnDelete,
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
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
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// ลบประวัติแชท: ห้องยังอยู่ แต่ข้อความเก่าทั้งหมดหายไปจากมุมมองของเรา
Future<void> confirmClearHistory(
  BuildContext context, {
  required String me,
  required String chatId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await _confirm(
    context,
    title: 'ลบประวัติแชท',
    message:
        'ข้อความเก่าทั้งหมดในห้องนี้จะหายไปจากฝั่งคุณเท่านั้น ส่วนอีกฝ่ายยังเห็นตามเดิม และห้องแชทยังอยู่ในรายการ',
    confirmLabel: 'ลบประวัติ',
  );
  if (!ok) return;
  try {
    await ChatService().clearHistory(me, chatId);
    messenger.showSnackBar(const SnackBar(content: Text('ลบประวัติแชทแล้ว')));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('ลบประวัติแชทไม่สำเร็จ: $e')),
    );
  }
}

/// ลบแชท: นำห้องออกจากรายการของเรา (ไม่กระทบอีกฝ่าย)
Future<void> confirmDeleteChat(
  BuildContext context, {
  required String me,
  required String chatId,
  bool isGroup = false,
  bool leaveScreenOnDelete = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final ok = await _confirm(
    context,
    title: 'ลบแชท',
    message: isGroup
        ? 'ห้องแชทนี้จะถูกนำออกจากรายการของคุณ แต่คุณยังเป็นสมาชิกกลุ่ม ถ้ามีข้อความใหม่ห้องจะกลับมาแสดง (ถ้าต้องการออกจากกลุ่มให้เลือก “ออกจากกลุ่ม”)'
        : 'ห้องแชทนี้จะถูกนำออกจากรายการของคุณ ถ้ามีข้อความใหม่ห้องจะกลับมาแสดงโดยเห็นเฉพาะข้อความใหม่',
    confirmLabel: 'ลบแชท',
  );
  if (!ok) return;
  try {
    await ChatService().deleteChat(me, chatId);
    try {
      if (isGroup) {
        await NotificationService().markGroupRead(me, chatId);
      } else {
        await NotificationService().markChatRead(me, chatId);
      }
    } catch (_) {
      // เคลียร์ตัวเลขแจ้งเตือนไม่ได้ก็ไม่กระทบการลบ
    }
    messenger.showSnackBar(const SnackBar(content: Text('ลบแชทแล้ว')));
    if (leaveScreenOnDelete && navigator.mounted) navigator.pop();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('ลบแชทไม่สำเร็จ: $e')));
  }
}
