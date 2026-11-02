import 'package:cloud_firestore/cloud_firestore.dart';

/// เวลาแบบสั้นอ่านง่าย เช่น "เมื่อสักครู่", "5 นาทีที่แล้ว", "3/11/2026"
String timeAgo(Timestamp? timestamp) {
  if (timestamp == null) return 'เมื่อสักครู่';
  final date = timestamp.toDate();
  final age = DateTime.now().difference(date);
  if (age.inSeconds < 60) return 'เมื่อสักครู่';
  if (age.inMinutes < 60) return '${age.inMinutes} นาทีที่แล้ว';
  if (age.inHours < 24) return '${age.inHours} ชั่วโมงที่แล้ว';
  if (age.inDays < 7) return '${age.inDays} วันที่แล้ว';
  return '${date.day}/${date.month}/${date.year}';
}
