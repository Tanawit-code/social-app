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
