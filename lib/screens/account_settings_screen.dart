import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/push_notification_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _auth = AuthService();
  final _db = FirebaseFirestore.instance;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  String get _uid => _auth.currentUser?.uid ?? '';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

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
    _email.text = _auth.currentUser?.email ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เปลี่ยนอีเมล'),
        content: TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'อีเมลใหม่'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _email.text.trim()),
            child: const Text('ส่งลิงก์ยืนยัน'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    await _run(
      () => _auth.changeEmail(value),
      'ส่งลิงก์ยืนยันไปยังอีเมลใหม่แล้ว',
    );
  }

  Future<void> _editPassword() async {
    _password.clear();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เปลี่ยนรหัสผ่าน'),
        content: TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'รหัสผ่านใหม่ (อย่างน้อย 6 ตัว)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _password.text),
            child: const Text('เปลี่ยนรหัสผ่าน'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    if (value.length < 6) {
      _message('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร');
      return;
    }
    await _run(() => _auth.changePassword(value), 'เปลี่ยนรหัสผ่านแล้ว');
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
