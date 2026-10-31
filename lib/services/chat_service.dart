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

  Future<void> ensureDirectChat(String me, String peer) async {
    if (me.isEmpty || peer.isEmpty || me == peer) return;
    final ref = _db.collection('chats').doc(chatId(me, peer));
    final snap = await ref.get();
    if (snap.exists) return;
    final participants = [me, peer]..sort();
    await ref.set({
      'type': 'direct',
      'participants': participants,
      'lastMessage': '',
      'lastAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String me, String peer) async* {
    await ensureDirectChat(me, peer);
    yield* _db
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

  Future<String> createGroup({
    required String ownerUid,
    required String name,
    required List<String> memberUids,
    String? photoUrl,
  }) async {
    final owner = await _db.collection('users').doc(ownerUid).get();
    final following = List<String>.from(owner.data()?['following'] ?? const []);
    final friends = <String>{};
    for (final uid in memberUids.toSet()) {
      if (uid == ownerUid || !following.contains(uid)) continue;
      final member = await _db.collection('users').doc(uid).get();
      final memberFollowing = List<String>.from(member.data()?['following'] ?? const []);
      if (memberFollowing.contains(ownerUid)) friends.add(uid);
    }
    if (friends.length != memberUids.toSet().length) {
      throw Exception('เพิ่มได้เฉพาะเพื่อนที่ติดตามกันทั้งสองฝ่าย');
    }
    final ref = _db.collection('chats').doc();
    final members = {...friends, ownerUid}.toList();
    await ref.set({
      'type': 'group',
      'name': name.trim(),
      'photoUrl': photoUrl ?? '',
      'backgroundColor': 0xFFF0F2F5,
      'participants': members,
      'ownerId': ownerUid,
      'lastMessage': 'สร้างกลุ่มแล้ว',
      'lastAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateGroup(String groupId, String uid, Map<String, dynamic> data) async {
    final ref = _db.collection('chats').doc(groupId);
    final snap = await ref.get();
    if (!snap.exists || snap.data()?['type'] != 'group' || snap.data()?['ownerId'] != uid) {
      throw Exception('เฉพาะเจ้าของกลุ่มเท่านั้นที่แก้ไขได้');
    }
    await ref.update(data);
  }

  Future<void> sendGroup({required String groupId, required String fromUid, String? text, String? imageUrl}) async {
    assert(text != null || imageUrl != null);
    final ref = _db.collection('chats').doc(groupId);
    final group = await ref.get();
    final data = group.data();
    final participants = List<String>.from(data?['participants'] ?? const []);
    if (!group.exists || data?['type'] != 'group' || !participants.contains(fromUid)) {
      throw Exception('คุณไม่ใช่สมาชิกของกลุ่มนี้');
    }
    final preview = imageUrl != null ? '📷 รูปภาพ' : text!;
    await ref.update({'lastMessage': preview, 'lastAt': FieldValue.serverTimestamp()});
    await ref.collection('messages').add({
      'senderId': fromUid,
      'text': text,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (final uid in participants.where((uid) => uid != fromUid)) {
      try {
        await NotificationService().create(
          toUid: uid,
          fromUid: fromUid,
          type: 'message',
          text: preview,
          groupId: groupId,
          groupName: data?['name'] as String? ?? 'กลุ่มแชท',
        );
      } catch (_) {
        // A notification write failure should not undo a sent message.
      }
    }
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
      chatId: chatId(fromUid, toUid),
    );
  }
}
