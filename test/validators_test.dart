import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_project/utils/validators.dart';

void main() {
  // ---------------------------------------------------------------
  group('isValidEmail', () {
    test('TC01 อีเมลรูปแบบถูกต้อง -> true', () {
      expect(isValidEmail('tanawit@gmail.com'), isTrue);
    });

    test('TC02 อีเมลมี . + - ในชื่อและโดเมนย่อย -> true', () {
      expect(isValidEmail('first.last+tag@mail.rmutt.ac.th'), isTrue);
    });

    test('TC03 มีช่องว่างหน้า-หลัง ระบบ trim ให้ -> true', () {
      expect(isValidEmail('  user@example.com  '), isTrue);
    });

    test('TC04 ไม่มีเครื่องหมาย @ -> false', () {
      expect(isValidEmail('userexample.com'), isFalse);
    });

    test('TC05 โดเมนไม่มีจุด (user@localhost) -> false', () {
      expect(isValidEmail('user@localhost'), isFalse);
    });

    test('TC06 สตริงว่าง -> false', () {
      expect(isValidEmail(''), isFalse);
    });
  });

  // ---------------------------------------------------------------
  group('validatePassword', () {
    test(
      'TC07 ยาว 7 ตัว (ต่ำกว่าขอบเขต 1 ตัว) -> แจ้งให้มีอย่างน้อย 8 ตัวอักษร',
      () {
        expect(
          validatePassword('abcde1!'),
          'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
        );
      },
    );

    test('TC08 ยาว 8 ตัวพอดี (ขอบเขต) และครบเงื่อนไข -> null', () {
      expect(validatePassword('abcdef1!'), isNull);
    });

    test('TC09 ไม่มีตัวเลข -> แจ้งให้มีตัวเลข', () {
      expect(
        validatePassword('abcdefgh!'),
        'รหัสผ่านต้องมีตัวเลขอย่างน้อย 1 ตัว',
      );
    });

    test('TC10 ไม่มีอักขระพิเศษ -> แจ้งให้มีอักขระพิเศษ', () {
      expect(
        validatePassword('abcdefg1'),
        'รหัสผ่านต้องมีอักขระพิเศษอย่างน้อย 1 ตัว (เช่น !@#\$%)',
      );
    });

    test('TC11 ช่องว่างไม่นับเป็นอักขระพิเศษ -> ไม่ผ่าน', () {
      expect(validatePassword('abc def1'), isNotNull);
    });

    test('TC12 รหัสผ่านแข็งแรง (ตัวอักษร+ตัวเลข+พิเศษ) -> null', () {
      expect(validatePassword('MyPass#2026'), isNull);
    });
  });

  // ---------------------------------------------------------------
  group('validateRegisterForm', () {
    String? run({
      String name = 'Tanawit',
      String email = 'tanawit@gmail.com',
      String password = 'MyPass#2026',
      String? confirm,
    }) => validateRegisterForm(
      name: name,
      email: email,
      password: password,
      confirm: confirm ?? password,
    );

    test('TC13 กรอกถูกต้องทั้งหมด -> null (ผ่าน)', () {
      expect(run(), isNull);
    });

    test('TC14 ชื่อว่าง -> กรุณากรอกข้อมูลให้ครบ', () {
      expect(run(name: ''), 'กรุณากรอกข้อมูลให้ครบ');
    });

    test('TC15 ชื่อเป็นช่องว่างล้วน -> กรุณากรอกข้อมูลให้ครบ', () {
      expect(run(name: '   '), 'กรุณากรอกข้อมูลให้ครบ');
    });

    test('TC16 อีเมลว่าง -> กรุณากรอกข้อมูลให้ครบ', () {
      expect(run(email: ''), 'กรุณากรอกข้อมูลให้ครบ');
    });

    test('TC17 อีเมลผิดรูปแบบ -> รูปแบบอีเมลไม่ถูกต้อง', () {
      expect(run(email: 'not-an-email'), 'รูปแบบอีเมลไม่ถูกต้อง');
    });

    test('TC18 รหัสผ่านอ่อนแอ -> คืนข้อความจาก validatePassword', () {
      expect(run(password: 'abc'), 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร');
    });

    test('TC19 ยืนยันรหัสผ่านไม่ตรง -> รหัสผ่านไม่ตรงกัน', () {
      expect(run(confirm: 'Different#123'), 'รหัสผ่านไม่ตรงกัน');
    });

    test(
      'TC20 มีหลายข้อผิดพร้อมกัน -> คืน error ข้อแรก (ข้อมูลไม่ครบก่อน)',
      () {
        expect(
          validateRegisterForm(
            name: '',
            email: 'bad',
            password: 'x',
            confirm: 'y',
          ),
          'กรุณากรอกข้อมูลให้ครบ',
        );
      },
    );
  });
}
