import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/safety_service.dart';
import '../utils/validators.dart';
import 'admin_reports_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _auth = AuthService();
  final _db = FirebaseFirestore.instance;
  bool _busy = false;
  late final Future<bool> _isAdmin = SafetyService.isAdmin();

  String get _uid => _auth.currentUser?.uid ?? '';

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _message(error ?? success);
  }

  Future<void> _refreshVerification() async {
    await _auth.reloadUser();
    final user = _auth.currentUser;
    if (user != null && user.emailVerified && user.email != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('private')
          .doc('account')
          .set({'email': user.email}, SetOptions(merge: true));
    }
    if (mounted) setState(() {});
    _message(
      user?.emailVerified == true
          ? 'ยืนยันอีเมลแล้ว'
          : 'ยังไม่พบการยืนยันอีเมล ลองเปิดลิงก์แล้วตรวจสอบอีกครั้ง',
    );
  }

  Future<void> _editEmail() async {
    final result = await showDialog<({String email, String password})>(
      context: context,
      builder: (_) =>
          _ChangeEmailDialog(currentEmail: _auth.currentUser?.email ?? ''),
    );
    if (result == null || !mounted) return;
    await _run(
      () => _auth.changeEmail(
        newEmail: result.email,
        currentPassword: result.password,
      ),
      'ส่งลิงก์ยืนยันไปยังอีเมลใหม่แล้ว อีเมลจะเปลี่ยนเมื่อคุณกดลิงก์ยืนยัน',
    );
  }

  Future<void> _editPassword() async {
    final result = await showDialog<({String current, String next})>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (result == null || !mounted) return;
    await _run(
      () => _auth.changePassword(
        currentPassword: result.current,
        newPassword: result.next,
      ),
      'เปลี่ยนรหัสผ่านแล้ว',
    );
  }

  Future<void> _setPreference(String key, bool value) async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('private')
          .doc('account')
          .set({key: value}, SetOptions(merge: true));
    } catch (error) {
      _message('บันทึกการตั้งค่าไม่สำเร็จ: $error');
    }
  }

  Future<void> _togglePush(bool value) async {
    setState(() => _busy = true);
    try {
      if (value) {
        final enabled = await PushNotificationService.instance.enableForUser(
          _uid,
        );
        if (mounted)
          _message(
            enabled
                ? 'เปิดการแจ้งเตือน Push แล้ว'
                : 'ไม่ได้รับอนุญาตให้ส่งการแจ้งเตือน กรุณาตรวจสอบการตั้งค่าอุปกรณ์',
          );
      } else {
        await PushNotificationService.instance.disableForUser(_uid);
        if (mounted) _message('ปิดการแจ้งเตือน Push แล้ว');
      }
    } catch (error) {
      _message('ตั้งค่าการแจ้งเตือนไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('บัญชีและการแจ้งเตือน')),
      body: user == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('users')
                  .doc(_uid)
                  .collection('private')
                  .doc('account')
                  .snapshots(),
              builder: (context, snapshot) {
                final prefs =
                    snapshot.data?.data() ?? const <String, dynamic>{};
                return ListView(
                  children: [
                    FutureBuilder<bool>(
                      future: _isAdmin,
                      builder: (context, adminSnap) => adminSnap.data == true
                          ? Column(
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                  ),
                                  title: const Text('รายงานทั้งหมด (แอดมิน)'),
                                  subtitle: const Text(
                                    'ตรวจสอบรายงานโพสต์ ผู้ใช้ เพจ ชุมชน และอื่นๆ',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AdminReportsScreen(),
                                    ),
                                  ),
                                ),
                                const Divider(),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    ListTile(
                      leading: Icon(
                        user.emailVerified
                            ? Icons.verified
                            : Icons.mark_email_unread_outlined,
                      ),
                      title: Text(user.email ?? 'ไม่มีอีเมล'),
                      subtitle: Text(
                        user.emailVerified
                            ? 'ยืนยันอีเมลแล้ว'
                            : 'ยังไม่ได้ยืนยันอีเมล',
                      ),
                      trailing: user.emailVerified
                          ? null
                          : TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      _auth.sendVerificationEmail,
                                      'ส่งอีเมลยืนยันแล้ว',
                                    ),
                              child: const Text('ส่งอีกครั้ง'),
                            ),
                    ),
                    if (!user.emailVerified)
                      ListTile(
                        leading: const Icon(Icons.refresh),
                        title: const Text('ตรวจสอบสถานะยืนยันอีเมล'),
                        onTap: _refreshVerification,
                      ),
                    ListTile(
                      leading: const Icon(Icons.alternate_email),
                      title: const Text('เปลี่ยนอีเมล'),
                      onTap: _busy ? null : _editEmail,
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: const Text('เปลี่ยนรหัสผ่าน'),
                      onTap: _busy ? null : _editPassword,
                    ),
                    const Divider(),
                    const ListTile(
                      title: Text(
                        'การแจ้งเตือน',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      value: prefs['pushEnabled'] == true,
                      onChanged: _busy ? null : _togglePush,
                      secondary: const Icon(
                        Icons.notifications_active_outlined,
                      ),
                      title: const Text('การแจ้งเตือนแบบ Push'),
                      subtitle: const Text('อนุญาตการแจ้งเตือนจากอุปกรณ์นี้'),
                    ),
                    SwitchListTile.adaptive(
                      value: prefs['messageNotifications'] != false,
                      onChanged: (value) =>
                          _setPreference('messageNotifications', value),
                      secondary: const Icon(Icons.chat_bubble_outline),
                      title: const Text('ข้อความใหม่'),
                    ),
                    SwitchListTile.adaptive(
                      value: prefs['socialNotifications'] != false,
                      onChanged: (value) =>
                          _setPreference('socialNotifications', value),
                      secondary: const Icon(Icons.favorite_border),
                      title: const Text('กิจกรรมทางสังคม'),
                      subtitle: const Text('การติดตาม ถูกใจ และความคิดเห็น'),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// Dialog เปลี่ยนอีเมล — เป็น StatefulWidget แยก เพื่อให้ State เป็นคน dispose
/// controller เองตอน dialog ถูกถอดออกจริง (ไม่ dispose ระหว่างแอนิเมชันปิด)
class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog({required this.currentEmail});

  final String currentEmail;

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final invalid = validateChangeEmailForm(
      currentEmail: widget.currentEmail,
      newEmail: _email.text,
      password: _password.text,
    );
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    Navigator.pop(context, (email: _email.text.trim(), password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เปลี่ยนอีเมล'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'อีเมลใหม่'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'รหัสผ่านปัจจุบัน (ยืนยันตัวตน)',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        FilledButton(onPressed: _submit, child: const Text('ส่งลิงก์ยืนยัน')),
      ],
    );
  }
}

/// Dialog เปลี่ยนรหัสผ่าน — รหัสใหม่ต้องมีอย่างน้อย 8 ตัว มีตัวเลขและอักขระพิเศษ
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final invalid = validateChangePasswordForm(
      current: _current.text,
      next: _next.text,
      confirm: _confirm.text,
    );
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    Navigator.pop(context, (current: _current.text, next: _next.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เปลี่ยนรหัสผ่าน'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _current,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _next,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'รหัสผ่านใหม่',
                helperText: 'อย่างน้อย 8 ตัวอักษร มีตัวเลขและอักขระพิเศษ',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่านใหม่'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        FilledButton(onPressed: _submit, child: const Text('เปลี่ยนรหัสผ่าน')),
      ],
    );
  }
}
