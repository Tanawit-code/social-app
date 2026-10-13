import 'package:cloud_firestore/cloud_firestore.dart';
import 'notification_service.dart';

/// แชท 1:1  chats/{chatId}  และ chats/{chatId}/messages
/// chatId = uid สองคนเรียงตัวอักษรแล้วต่อด้วย _  (คู่เดิมได้ห้องเดิมเสมอ)
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String chatId(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String me, String peer) {
    return _db
        .collection('chats')
        .doc(chatId(me, peer))
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  /// รายการห้องแชทของ uid (เรียงใหม่สุดฝั่ง client เพื่อไม่ต้องสร้าง composite index)
  Stream<QuerySnapshot<Map<String, dynamic>>> chats(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots();
  }

  Future<void> send({
    required String fromUid,
    required String toUid,
    String? text,
    String? imageUrl,
  }) async {
    assert(text != null || imageUrl != null);
    final ref = _db.collection('chats').doc(chatId(fromUid, toUid));
    final preview = imageUrl != null ? '📷 รูปภาพ' : text!;

    await ref.set({
      'participants': [fromUid, toUid],
      'lastMessage': preview,
      'lastAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await ref.collection('messages').add({
      'senderId': fromUid,
      'text': text,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await NotificationService().create(
      toUid: toUid,
      fromUid: fromUid,
      type: 'message',
      text: preview,
    );
  }
}
