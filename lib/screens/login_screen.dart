import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _rememberKey = 'login_remember_email';
  static const _emailKey = 'login_saved_email';

  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _loading = false;
  bool _rememberMe = true;
  String? _error;
  DateTime? _resetCooldownUntil;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// จำอีเมลล่าสุดไว้ในเครื่อง (ไม่เก็บรหัสผ่านเด็ดขาด)
  Future<void> _loadSavedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remember = prefs.getBool(_rememberKey) ?? true;
      final email = prefs.getString(_emailKey) ?? '';
      if (!mounted) return;
      setState(() {
        _rememberMe = remember;
        if (remember && email.isNotEmpty) _emailController.text = email;
      });
    } catch (_) {
      // อ่านค่าไม่ได้ = เริ่มจากฟอร์มว่าง
    }
  }

  Future<void> _saveEmailPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberKey, _rememberMe);
      if (_rememberMe) {
        await prefs.setString(_emailKey, _emailController.text.trim());
      } else {
        await prefs.remove(_emailKey);
      }
    } catch (_) {}
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validateEmail(String? v) {
    final email = (v ?? '').trim();
    if (email.isEmpty) return 'กรุณากรอกอีเมล';
    if (!isValidEmail(email)) return 'รูปแบบอีเมลไม่ถูกต้อง';
    return null;
  }

  String? _validatePassword(String? v) =>
      (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null;

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.lightImpact();
      return;
    }

    setState(() => _loading = true);
    final error = await _authService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      HapticFeedback.mediumImpact();
      setState(() => _error = error);
      return;
    }
    await _saveEmailPreference();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!isValidEmail(email)) {
      _showMessage('กรอกอีเมลที่ถูกต้องก่อนขอลิงก์ตั้งรหัสผ่านใหม่');
      return;
    }
    final until = _resetCooldownUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final left = until.difference(DateTime.now()).inSeconds + 1;
      _showMessage('ขอลิงก์ได้อีกครั้งในอีก $left วินาที');
      return;
    }
    setState(() => _loading = true);
    final error = await _authService.sendPasswordReset(email);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error == null) {
      _resetCooldownUntil = DateTime.now().add(const Duration(seconds: 60));
    }
    _showMessage(
      error ?? 'ส่งลิงก์ตั้งรหัสผ่านใหม่แล้ว โปรดตรวจกล่องอีเมล (รวมถึงอีเมลขยะ)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthScaffold(
      title: 'ยินดีต้อนรับกลับมา',
      subtitle: 'เข้าสู่ระบบเพื่อพูดคุยกับเพื่อนๆ ของคุณ',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InlineErrorBanner(message: _error),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateEmail,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: authInputDecoration(
                  context,
                  label: 'อีเมล',
                  icon: Icons.mail_outline_rounded,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: _validatePassword,
                onFieldSubmitted: (_) => _loading ? null : _handleLogin(),
                decoration: authInputDecoration(
                  context,
                  label: 'รหัสผ่าน',
                  icon: Icons.lock_outline_rounded,
                  suffix: IconButton(
                    tooltip: _obscurePassword ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? false),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'จำอีเมลไว้',
                                style: TextStyle(fontSize: 13.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _resetPassword,
                    child: const Text('ลืมรหัสผ่าน?'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PrimaryLoadingButton(
                label: 'เข้าสู่ระบบ',
                loading: _loading,
                onPressed: _handleLogin,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'หรือ',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.pushNamed(context, '/register'),
                  child: const Text(
                    'สร้างบัญชีใหม่',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
