import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  static final _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validate() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      return 'กรุณากรอกอีเมลและรหัสผ่าน';
    }
    if (!_emailRegex.hasMatch(email)) {
      return 'รูปแบบอีเมลไม่ถูกต้อง';
    }
    return null;
  }

  Future<void> _handleLogin() async {
    final validationError = _validate();
    if (validationError != null) {
      _showMessage(validationError);
      return;
    }

    setState(() => _loading = true);
    // ถ้าอีเมลนี้ยังไม่เคยลงทะเบียน auth_service จะคืน error กลับมา
    // ("ยังไม่มีบัญชีนี้ในระบบ กรุณาสมัครสมาชิกก่อน") ทำให้เข้าหน้า Feed ไม่ได้
    final error = await _authService.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    setState(() => _loading = false);

    if (error != null) {
      _showMessage(error);
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!_emailRegex.hasMatch(email)) {
      _showMessage('กรอกอีเมลที่ถูกต้องก่อนขอลิงก์ตั้งรหัสผ่านใหม่');
      return;
    }
    setState(() => _loading = true);
    final error = await _authService.sendPasswordReset(email);
    if (!mounted) return;
    setState(() => _loading = false);
    _showMessage(error ?? 'ส่งลิงก์ตั้งรหัสผ่านใหม่แล้ว โปรดตรวจกล่องอีเมล');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.group, size: 72, color: Colors.deepPurple),
                const SizedBox(height: 12),
                const Text(
                  'เข้าสู่ระบบ',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading ? null : _resetPassword,
                    child: const Text('ลืมรหัสผ่าน?'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _handleLogin,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('เข้าสู่ระบบ'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/register');
                  },
                  child: const Text('ยังไม่มีบัญชี? สมัครสมาชิก'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
