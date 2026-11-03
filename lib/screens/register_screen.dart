import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _acceptTerms = false;
  bool _termsError = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // อัปเดตแถบความแข็งแรงของรหัสผ่านทุกครั้งที่พิมพ์
    _passwordController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    final name = (v ?? '').trim();
    if (name.isEmpty) return 'กรุณากรอกชื่อ-นามสกุล';
    if (name.length < 2) return 'ชื่อสั้นเกินไป';
    return null;
  }

  String? _validateEmail(String? v) {
    final email = (v ?? '').trim();
    if (email.isEmpty) return 'กรุณากรอกอีเมล';
    if (!isValidEmail(email)) return 'รูปแบบอีเมลไม่ถูกต้อง';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'กรุณากรอกรหัสผ่าน';
    return validatePassword(v);
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'กรุณายืนยันรหัสผ่าน';
    if (v != _passwordController.text) return 'รหัสผ่านไม่ตรงกัน';
    return null;
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _termsError = !_acceptTerms;
    });

    final formOk = _formKey.currentState?.validate() ?? false;
    // ตรวจซ้ำด้วยฟังก์ชันกลาง (ชุดเดียวกับที่มี unit test) กันหลุดเงื่อนไข
    final serverRuleError = validateRegisterForm(
      name: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      confirm: _confirmController.text,
    );
    if (!formOk || serverRuleError != null || !_acceptTerms) {
      HapticFeedback.lightImpact();
      return;
    }

    setState(() => _loading = true);
    final error = await _authService.register(
      name: _nameController.text.trim(),
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
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      title: 'สร้างบัญชีใหม่',
      subtitle: 'ใช้เวลาไม่ถึงหนึ่งนาที แล้วมาเริ่มต้นไปด้วยกัน',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InlineErrorBanner(message: _error),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateName,
                onFieldSubmitted: (_) => _emailFocus.requestFocus(),
                decoration: authInputDecoration(
                  context,
                  label: 'ชื่อ-นามสกุล',
                  icon: Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                focusNode: _emailFocus,
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
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validatePassword,
                onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
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
              PasswordStrengthMeter(password: _passwordController.text),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmController,
                focusNode: _confirmFocus,
                obscureText: _obscureConfirm,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _validateConfirm,
                onFieldSubmitted: (_) => _loading ? null : _handleRegister(),
                decoration: authInputDecoration(
                  context,
                  label: 'ยืนยันรหัสผ่าน',
                  icon: Icons.lock_reset_rounded,
                  suffix: IconButton(
                    tooltip: _obscureConfirm ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() {
                  _acceptTerms = !_acceptTerms;
                  _termsError = false;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _acceptTerms,
                          isError: _termsError,
                          onChanged: (v) => setState(() {
                            _acceptTerms = v ?? false;
                            _termsError = false;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ฉันยอมรับข้อตกลงการใช้งานและนโยบายความเป็นส่วนตัว',
                          style: TextStyle(
                            fontSize: 13,
                            color: _termsError
                                ? Colors.red.shade700
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              PrimaryLoadingButton(
                label: 'สมัครสมาชิก',
                loading: _loading,
                onPressed: _handleRegister,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'มีบัญชีอยู่แล้ว?',
                    style: TextStyle(fontSize: 13.5),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => Navigator.maybePop(context),
                    child: const Text('เข้าสู่ระบบ'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
