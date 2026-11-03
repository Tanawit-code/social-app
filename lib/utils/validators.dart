/// ตรวจฟอร์มฝั่ง client (แยกออกมาเป็นฟังก์ชันล้วน เพื่อให้เขียน unit test ได้โดยไม่ต้องใช้ Firebase)

final _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');
final _digitRegex = RegExp(r'[0-9]');
final _specialRegex = RegExp(r'[^A-Za-z0-9\s]');

bool isValidEmail(String email) => _emailRegex.hasMatch(email.trim());

/// คืนข้อความ error ถ้ารหัสผ่านไม่ผ่านเกณฑ์ หรือ null ถ้าผ่าน
String? validatePassword(String password) {
  if (password.length < 8) return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
  if (!_digitRegex.hasMatch(password)) {
    return 'รหัสผ่านต้องมีตัวเลขอย่างน้อย 1 ตัว';
  }
  if (!_specialRegex.hasMatch(password)) {
    return 'รหัสผ่านต้องมีอักขระพิเศษอย่างน้อย 1 ตัว (เช่น !@#\$%)';
  }
  return null;
}

/// ตรวจฟอร์มเปลี่ยนรหัสผ่าน คืน error ข้อแรกที่เจอ หรือ null ถ้าผ่านหมด
String? validateChangePasswordForm({
  required String current,
  required String next,
  required String confirm,
}) {
  if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
    return 'กรุณากรอกข้อมูลให้ครบ';
  }
  final pw = validatePassword(next);
  if (pw != null) return pw;
  if (next == current) return 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม';
  if (next != confirm) return 'รหัสผ่านไม่ตรงกัน';
  return null;
}

/// ตรวจฟอร์มเปลี่ยนอีเมล คืน error ข้อแรกที่เจอ หรือ null ถ้าผ่านหมด
String? validateChangeEmailForm({
  required String currentEmail,
  required String newEmail,
  required String password,
}) {
  if (newEmail.trim().isEmpty || password.isEmpty) {
    return 'กรุณากรอกข้อมูลให้ครบ';
  }
  if (!isValidEmail(newEmail)) return 'รูปแบบอีเมลไม่ถูกต้อง';
  if (newEmail.trim().toLowerCase() == currentEmail.trim().toLowerCase()) {
    return 'อีเมลใหม่ต้องไม่ซ้ำกับอีเมลปัจจุบัน';
  }
  return null;
}

/// ตรวจฟอร์มสมัครสมาชิกทั้งฟอร์ม คืน error ข้อแรกที่เจอ หรือ null ถ้าผ่านหมด
String? validateRegisterForm({
  required String name,
  required String email,
  required String password,
  required String confirm,
}) {
  if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
    return 'กรุณากรอกข้อมูลให้ครบ';
  }
  if (!isValidEmail(email)) return 'รูปแบบอีเมลไม่ถูกต้อง';
  final pw = validatePassword(password);
  if (pw != null) return pw;
  if (password != confirm) return 'รหัสผ่านไม่ตรงกัน';
  return null;
}

/// ความแข็งแรงของรหัสผ่าน 0-4 (0 = ว่าง, 1 = อ่อนมาก ... 4 = แข็งแรง)
/// ใช้แสดงแถบสีตอนสมัครสมาชิก — ไม่ได้แทนเกณฑ์ขั้นต่ำของ [validatePassword]
int passwordStrength(String password) {
  if (password.isEmpty) return 0;
  var score = 0;
  if (password.length >= 8) score++;
  if (_digitRegex.hasMatch(password)) score++;
  if (_specialRegex.hasMatch(password)) score++;
  if (password.length >= 12 &&
      RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[A-Z]').hasMatch(password)) {
    score++;
  }
  return score.clamp(1, 4);
}
