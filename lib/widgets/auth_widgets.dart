import 'package:flutter/material.dart';
import '../utils/validators.dart';

/// โครงหน้า Login / Register: หัวไล่สีธีม + โลโก้ แล้วมีการ์ดสีขาวมนซ้อนขึ้นมา
/// ใช้สีจากธีมที่ผู้ใช้เลือก จึงเปลี่ยนตามธีมของแอปอัตโนมัติ
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  /// true = แสดงปุ่มย้อนกลับมุมซ้ายบน (หน้า Register)
  final bool showBack;

  const AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final dark = Color.lerp(primary, Colors.black, 0.4)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: GestureDetector(
        // แตะพื้นที่ว่างเพื่อปิดคีย์บอร์ด
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // หัวไล่สี: สูงตามเนื้อหาจริง จึงไม่มีอะไรถูกการ์ดขาวบัง
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(32),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primary, dark],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Stack(
                    children: [
                      const Positioned(
                        top: -40,
                        right: -30,
                        child: _Bubble(size: 170, opacity: 0.10),
                      ),
                      const Positioned(
                        bottom: -40,
                        left: -50,
                        child: _Bubble(size: 130, opacity: 0.08),
                      ),
                      SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                          child: Column(
                            children: [
                              if (showBack)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    tooltip: 'ย้อนกลับ',
                                    color: Colors.white,
                                    icon: const Icon(Icons.arrow_back_ios_new),
                                    onPressed: () =>
                                        Navigator.maybePop(context),
                                  ),
                                )
                              else
                                const SizedBox(height: 24),
                              const _LogoBadge(),
                              const SizedBox(height: 14),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 14.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: child,
                    ),
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

class _Bubble extends StatelessWidget {
  final double size;
  final double opacity;
  const _Bubble({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white.withValues(alpha: opacity),
    ),
  );
}

class _LogoBadge extends StatelessWidget {
  const _LogoBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          Icons.forum_rounded,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// ช่องกรอกข้อมูลสไตล์เดียวกันทั้งแอป (พื้นเทาอ่อน ไม่มีขอบตอนปกติ)
InputDecoration authInputDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  String? hint,
  Widget? suffix,
}) {
  final primary = Theme.of(context).colorScheme.primary;
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFFF5F6F8),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(Colors.transparent),
    enabledBorder: border(const Color(0xFFE4E6EB)),
    focusedBorder: border(primary, 2),
    errorBorder: border(Colors.red.shade400),
    focusedErrorBorder: border(Colors.red.shade600, 2),
  );
}

/// แถบบอกความแข็งแรงของรหัสผ่านแบบ real-time + เช็กลิสต์เงื่อนไข
class PasswordStrengthMeter extends StatelessWidget {
  final String password;
  const PasswordStrengthMeter({required this.password, super.key});

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final level = passwordStrength(password);
    final info = _levelInfo(level);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 0; i < 4; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 5,
                    margin: EdgeInsets.only(right: i == 3 ? 0 : 5),
                    decoration: BoxDecoration(
                      color: i < level ? info.color : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Text(
                info.label,
                style: TextStyle(
                  color: info.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Rule('8 ตัวอักษรขึ้นไป', password.length >= 8),
              _Rule('มีตัวเลข', RegExp(r'[0-9]').hasMatch(password)),
              _Rule(
                'มีอักขระพิเศษ',
                RegExp(r'[^A-Za-z0-9\s]').hasMatch(password),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ({Color color, String label}) _levelInfo(int level) {
    switch (level) {
      case 1:
        return (color: Colors.red.shade600, label: 'อ่อนมาก');
      case 2:
        return (color: Colors.orange.shade700, label: 'พอใช้');
      case 3:
        return (color: Colors.lightGreen.shade700, label: 'ดี');
      case 4:
        return (color: Colors.green.shade700, label: 'แข็งแรง');
      default:
        return (color: Colors.grey, label: '');
    }
  }
}

class _Rule extends StatelessWidget {
  final String text;
  final bool ok;
  const _Rule(this.text, this.ok);

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.green.shade700 : Colors.grey.shade600;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

/// กล่องแสดงข้อผิดพลาดในฟอร์ม (แทนที่การโชว์แค่ SnackBar ที่หายเร็ว)
class InlineErrorBanner extends StatelessWidget {
  final String? message;
  const InlineErrorBanner({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 20, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message!,
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// ปุ่มหลักเต็มความกว้าง พร้อมสถานะกำลังโหลด
class PrimaryLoadingButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  const PrimaryLoadingButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: loading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  key: const ValueKey('label'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
