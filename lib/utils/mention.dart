/// รูปแบบการแท็กที่เก็บใน text ของโพสต์/คอมเมนต์: `@[ชื่อ](uid)`
/// - ไม่ต้องเพิ่มฟิลด์ใหม่ใน Firestore (rules เดิมใช้ได้) เพราะดึง uid จาก text เอง
/// - ถ้าแสดงผลโดยไม่ผ่าน [MentionText] จะอ่านได้เป็น `@ชื่อ` ด้วย [Mention.plain]
class Mention {
  static final RegExp pattern = RegExp(
    r'@\[([^\]\n]{1,60})\]\(([A-Za-z0-9_-]{1,128})\)',
  );

  static String token(String name, String uid) =>
      '@[${name.replaceAll(RegExp(r'[\[\]()\n]'), '').trim()}]($uid)';

  /// uid ทั้งหมดที่ถูกแท็กใน [text]
  static Set<String> uids(String? text) => text == null || text.isEmpty
      ? <String>{}
      : pattern.allMatches(text).map((m) => m.group(2)!).toSet();

  /// แปลง `@[ชื่อ](uid)` เป็น `@ชื่อ` สำหรับแสดงเป็นข้อความธรรมดา (พรีวิว/แชร์/แจ้งเตือน)
  static String plain(String? text) => (text ?? '').replaceAllMapped(
    pattern,
    (m) => '@${m.group(1)}',
  );
}
