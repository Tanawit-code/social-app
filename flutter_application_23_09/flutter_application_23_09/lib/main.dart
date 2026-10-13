/*
  ขั้นตอนต่อไปจะเป็นการอัพเดทแอปให้มีฟังก์ชันมากยิ่งขึ้น
  ฟังก์ชันที่เพิ่มคือการเพิ่มวิดีโอตัวอย่างหนัง
  ใช้ library ชื่อ youtube_player_flutter: ^9.1.2  < เพิ่มใน pubspec.yaml
  ศึกษาการใช้งานได้จาก > https://pub.dev/packages/youtube_player_flutter


*/





import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// จุดเริ่มต้นของแอพ
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ต้องรอให้โหลด .env เสร็จก่อน
  try {
    await dotenv.load(fileName: ".env");
  } catch (error) {
    debugPrint('Unable to load .env: $error');
  }

  // ProviderScope คือ widget พิเศษที่ทำให้ Riverpod สามารถทำงานได้
  // ถ้าไม่ใส่ ProviderScope จะใช้งาน provider ไม่ได้
  runApp(const ProviderScope(child: MyApp()));
}

// MyApp เป็น widget หลักของแอพ
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MaterialApp เป็น root widget ของ Flutter app
    return MaterialApp(
      title: 'Movie Explorer', // ชื่อแอพ (แสดงใน task manager หรือบาง platform)
      theme: ThemeData.dark().copyWith(
    scaffoldBackgroundColor: Colors.black, // พื้นหลังดำสนิท
    primaryColor: Colors.pinkAccent,        // สีหลัก Neon Pink
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,       // AppBar ดำ
      foregroundColor: Colors.pinkAccent,  // Title สี Neon Pink
    ),
    textTheme: ThemeData.dark().textTheme.copyWith(
      bodyLarge: const TextStyle(color: Colors.yellowAccent),
      bodyMedium: const TextStyle(color: Colors.cyanAccent),
      titleLarge: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.cyanAccent,
        foregroundColor: Colors.black,
      ),
    ),
    cardTheme: CardThemeData(
      //color: Colors.red.withOpacity(0.2),   // ปรับเป็นเทาเข้ม / เพิ่มขอบ Neon ได้
      shadowColor: Colors.pinkAccent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: const BorderSide(
          color: Colors.pinkAccent,        // ขอบ Neon
          width: 2,
        ),
      ),
    ),
  ), // ธีมสีหลักของแอพ
      debugShowCheckedModeBanner: false, // เอาป้าย DEBUG ออก
      home: const HomeScreen(), // หน้าแรกที่จะถูกแสดง
    );
  }
}
