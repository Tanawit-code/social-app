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
    try {
      final snap = await ref.get();
      if (snap.exists) return;
    } on FirebaseException catch (e) {
      // ห้องยังไม่มี + rules เดิมปฏิเสธการ get -> ไปสร้างห้องต่อ
      if (e.code != 'permission-denied') rethrow;
    }
    final participants = [me, peer]..sort();
    await ref.set({
      'type': 'direct',
      'participants': participants,
      'lastMessage': '',
      'lastAt': FieldValue.serverTimestamp(),
    });
  }

  /// since = เวลาที่ผู้ใช้กด "ลบประวัติแชท" ล่าสุด (แสดงเฉพาะข้อความหลังเวลานั้น)
  Stream<QuerySnapshot<Map<String, dynamic>>> messages(
    String me,
    String peer, {
    Timestamp? since,
  }) async* {
    await ensureDirectChat(me, peer);
    yield* messagesSince(chatId(me, peer), since);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesSince(
    String chatId,
    Timestamp? since,
  ) {
    Query<Map<String, dynamic>> q = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true);
    if (since != null) q = q.where('createdAt', isGreaterThan: since);
    return q.limit(100).snapshots();
  }

  // ---------- สถานะแชทรายคน: users/{uid}/chatStates/{chatId} ----------
  // clearedAt = เวลาลบประวัติ (ซ่อนข้อความก่อนหน้านี้) / deletedAt = เวลาลบแชท (ซ่อนห้องจนกว่าจะมีข้อความใหม่)

  CollectionReference<Map<String, dynamic>> _states(String uid) =>
      _db.collection('users').doc(uid).collection('chatStates');

  Stream<DocumentSnapshot<Map<String, dynamic>>> chatState(
    String uid,
    String chatId,
  ) => _states(uid).doc(chatId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> chatStates(String uid) =>
      _states(uid).snapshots();

  /// ลบประวัติแชท (ห้องยังอยู่ในรายการ)
  Future<void> clearHistory(String uid, String chatId) =>
      _states(uid).doc(chatId).set({
        'clearedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// ลบแชท (นำห้องออกจากรายการ + ล้างประวัติฝั่งเราด้วย)
  Future<void> deleteChat(String uid, String chatId) =>
      _states(uid).doc(chatId).set({
        'clearedAt': FieldValue.serverTimestamp(),
        'deletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// ห้องถูกซ่อนหรือไม่: ลบแชทไว้ และยังไม่มีข้อความใหม่หลังเวลาที่ลบ
  static bool isHidden(Map<String, dynamic>? state, Map<String, dynamic> chat) {
    final deletedAt = state?['deletedAt'] as Timestamp?;
    if (deletedAt == null) return false;
    final lastAt = chat['lastAt'] as Timestamp?;
    if (lastAt == null) return false; // กำลังส่งข้อความ
    return !lastAt.toDate().isAfter(deletedAt.toDate());
  }

  /// ตัวอย่างข้อความล่าสุดในรายการ: ถ้าลบประวัติไว้และยังไม่มีข้อความใหม่ ให้ว่าง
  static String previewFor(
    Map<String, dynamic>? state,
    Map<String, dynamic> chat,
  ) {
    final clearedAt = state?['clearedAt'] as Timestamp?;
    final lastAt = chat['lastAt'] as Timestamp?;
    if (clearedAt != null &&
        lastAt != null &&
        !lastAt.toDate().isAfter(clearedAt.toDate())) {
      return '';
    }
    return chat['lastMessage'] as String? ?? '';
  }

  // ---------- สมาชิกกลุ่ม ----------

  /// ออกจากกลุ่มเอง — เจ้าของกลุ่มออกได้: โอนความเป็นเจ้าของให้สมาชิกคนถัดไป
  /// ถ้าไม่มีสมาชิกอื่นเหลือ กลุ่มจะถูกลบ
  Future<void> leaveGroup({
    required String groupId,
    required String uid,
  }) async {
    final ref = _db.collection('chats').doc(groupId);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists || data?['type'] != 'group') {
      throw Exception('ไม่พบกลุ่มนี้');
    }
    final participants = List<String>.from(data?['participants'] ?? const []);
    if (!participants.contains(uid)) {
      throw Exception('คุณไม่ได้เป็นสมาชิกของกลุ่มนี้');
    }
    if (data?['ownerId'] == uid) {
      final others = participants.where((u) => u != uid).toList();
      if (others.isEmpty) {
        await ref.delete();
        return;
      }
      await ref.update({
        'participants': FieldValue.arrayRemove([uid]),
        'ownerId': others.first,
      });
      try {
        await _states(uid).doc(groupId).delete();
      } catch (_) {}
      return;
    }
    await ref.update({
      'participants': FieldValue.arrayRemove([uid]),
    });
    // ล้างสถานะ "ลบแชท" ของกลุ่มนี้ เผื่อถูกเพิ่มกลับเข้ากลุ่มทีหลังจะได้เห็นห้องตามปกติ
    try {
      await _states(uid).doc(groupId).delete();
    } catch (_) {}
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _safeUser(String uid) async {
    try {
      return await _db.collection('users').doc(uid).get();
    } catch (_) {
      return null;
    }
  }

  /// เพื่อนที่ "ติดตามกันทั้งสองฝ่าย" (เงื่อนไขเดียวกับตอนสร้างกลุ่ม)
  /// exclude = uid ที่ไม่ต้องการ เช่นสมาชิกที่อยู่ในกลุ่มแล้ว
  Future<List<DocumentSnapshot<Map<String, dynamic>>>> mutualFriends(
    String uid, {
    Set<String> exclude = const {},
  }) async {
    final me = await _db.collection('users').doc(uid).get();
    final following = List<String>.from(
      me.data()?['following'] ?? const [],
    ).where((u) => u != uid && !exclude.contains(u)).take(200).toList();
    final docs = await Future.wait(following.map(_safeUser));
    return [
      for (final d in docs)
        if (d != null &&
            d.exists &&
            List<String>.from(d.data()?['following'] ?? const []).contains(uid))
          d,
    ];
  }

  /// เจ้าของกลุ่มเพิ่มเพื่อนเข้ากลุ่ม (เพิ่มได้เฉพาะเพื่อนที่ติดตามกันทั้งสองฝ่าย รวมไม่เกิน 50 คน)
  Future<int> addMembers({
    required String groupId,
    required String ownerUid,
    required List<String> memberUids,
  }) async {
    final ref = _db.collection('chats').doc(groupId);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists ||
        data?['type'] != 'group' ||
        data?['ownerId'] != ownerUid) {
      throw Exception('เฉพาะเจ้าของกลุ่มเท่านั้นที่เพิ่มสมาชิกได้');
    }
    final current = List<String>.from(data?['participants'] ?? const []);
    final toAdd = memberUids
        .toSet()
        .where((u) => u != ownerUid && !current.contains(u))
        .toList();
    if (toAdd.isEmpty) return 0;
    if (current.length + toAdd.length > 50) {
      throw Exception('กลุ่มมีสมาชิกได้สูงสุด 50 คน');
    }
    final owner = await _db.collection('users').doc(ownerUid).get();
    final ownerFollowing = List<String>.from(
      owner.data()?['following'] ?? const [],
    );
    for (final uid in toAdd) {
      var ok = ownerFollowing.contains(uid);
      if (ok) {
        final member = await _db.collection('users').doc(uid).get();
        ok = List<String>.from(
          member.data()?['following'] ?? const [],
        ).contains(ownerUid);
      }
      if (!ok) throw Exception('เพิ่มได้เฉพาะเพื่อนที่ติดตามกันทั้งสองฝ่าย');
    }
    await ref.update({'participants': FieldValue.arrayUnion(toAdd)});
    return toAdd.length;
  }

  /// เจ้าของกลุ่มเตะสมาชิกออกจากกลุ่ม
  Future<void> removeMember({
    required String groupId,
    required String ownerUid,
    required String memberUid,
  }) async {
    if (memberUid == ownerUid) throw Exception('เตะเจ้าของกลุ่มไม่ได้');
    final ref = _db.collection('chats').doc(groupId);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists ||
        data?['type'] != 'group' ||
        data?['ownerId'] != ownerUid) {
      throw Exception('เฉพาะเจ้าของกลุ่มเท่านั้นที่เตะสมาชิกได้');
    }
    await ref.update({
      'participants': FieldValue.arrayRemove([memberUid]),
    });
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
      final memberFollowing = List<String>.from(
        member.data()?['following'] ?? const [],
      );
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

  Future<void> updateGroup(
    String groupId,
    String uid,
    Map<String, dynamic> data,
  ) async {
    final ref = _db.collection('chats').doc(groupId);
    final snap = await ref.get();
    if (!snap.exists ||
        snap.data()?['type'] != 'group' ||
        snap.data()?['ownerId'] != uid) {
      throw Exception('เฉพาะเจ้าของกลุ่มเท่านั้นที่แก้ไขได้');
    }
    await ref.update(data);
  }

  /// ตัวอย่างข้อความล่าสุดในรายการแชท (ข้อความ / รูป / วิดีโอ)
  static String _preview({
    String? text,
    String? imageUrl,
    List<String> moreImageUrls = const [],
    String? videoUrl,
    Map<String, dynamic>? sharedPost,
  }) {
    if (videoUrl != null) return '🎬 วิดีโอ';
    if (imageUrl != null) {
      final count = 1 + moreImageUrls.length;
      return count > 1 ? '📷 รูปภาพ $count รูป' : '📷 รูปภาพ';
    }
    if (sharedPost != null && (text == null || text.trim().isEmpty)) {
      return '🔗 แชร์โพสต์';
    }
    return text!;
  }

  /// ฟิลด์สื่อของข้อความ: imageUrl = รูปแรก, moreImageUrls = รูปที่เหลือ, videoUrl = วิดีโอ
  static Map<String, dynamic> _mediaFields({
    String? imageUrl,
    List<String> moreImageUrls = const [],
    String? videoUrl,
    Map<String, dynamic>? sharedPost,
  }) => {
    'imageUrl': imageUrl,
    if (moreImageUrls.isNotEmpty) 'moreImageUrls': moreImageUrls,
    if (videoUrl != null) 'videoUrl': videoUrl,
    // อ้างอิงโพสต์ที่แชร์ (เก็บแค่ id — เนื้อหาโหลดสดตอนแสดง ให้ rules ตัดสินสิทธิ์ดู)
    if (sharedPost != null) 'sharedPost': sharedPost,
  };

  /// อ้างอิงโพสต์ที่แนบไปกับข้อความแชท (เก็บเฉพาะ id ไม่คัดลอกเนื้อหา)
  /// kind = 'post' (โพสต์ฟีด) | 'page_post' (โพสต์ในเพจ) | 'community_post' (โพสต์ในชุมชน)
  static Map<String, dynamic> postRef({
    required String kind,
    required String postId,
    String? communityId,
    String? pageId,
  }) => {
    'kind': kind,
    'postId': postId,
    if (communityId != null) 'communityId': communityId,
    if (pageId != null) 'pageId': pageId,
  };

  Future<void> sendGroup({
    required String groupId,
    required String fromUid,
    String? text,
    String? imageUrl,
    List<String> moreImageUrls = const [],
    String? videoUrl,
    Map<String, dynamic>? sharedPost,
  }) async {
    assert(
      text != null || imageUrl != null || videoUrl != null || sharedPost != null,
    );
    final ref = _db.collection('chats').doc(groupId);
    final group = await ref.get();
    final data = group.data();
    final participants = List<String>.from(data?['participants'] ?? const []);
    if (!group.exists ||
        data?['type'] != 'group' ||
        !participants.contains(fromUid)) {
      throw Exception('คุณไม่ใช่สมาชิกของกลุ่มนี้');
    }
    final preview = _preview(
      text: text,
      imageUrl: imageUrl,
      moreImageUrls: moreImageUrls,
      videoUrl: videoUrl,
      sharedPost: sharedPost,
    );
    await ref.update({
      'lastMessage': preview,
      'lastAt': FieldValue.serverTimestamp(),
    });
    await ref.collection('messages').add({
      'senderId': fromUid,
      'text': text,
      ..._mediaFields(
        imageUrl: imageUrl,
        moreImageUrls: moreImageUrls,
        videoUrl: videoUrl,
        sharedPost: sharedPost,
      ),
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

  /// ลบข้อความแบบ "ข้อความถูกลบ" (ให้ทุกคนในห้องเห็นเป็นกล่องว่างที่เขียนว่าข้อความถูกลบ)
  /// ล้างเนื้อหา text/imageUrl ทิ้งจริง แล้วใส่ deleted: true
  /// rules: เจ้าของข้อความ หรือเจ้าของกลุ่มเท่านั้น
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    final chat = _db.collection('chats').doc(chatId);
    await chat.collection('messages').doc(messageId).update({
      'deleted': true,
      'text': null,
      'imageUrl': null,
      // ลบฟิลด์สื่อรุ่นใหม่ด้วย (ถ้าข้อความไม่มีฟิลด์นี้ จะไม่มีอะไรเปลี่ยน)
      'moreImageUrls': FieldValue.delete(),
      'videoUrl': FieldValue.delete(),
      'sharedPost': FieldValue.delete(),
    });
    try {
      // ถ้าข้อความที่ลบเป็นข้อความล่าสุด ให้รายการแชทแสดง "ข้อความถูกลบ" ด้วย
      final latest = await chat
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (latest.docs.isNotEmpty && latest.docs.first.id == messageId) {
        await chat.update({'lastMessage': 'ข้อความถูกลบ'});
      }
    } catch (_) {
      // ลบข้อความสำเร็จแล้ว ถ้าอัปเดตตัวอย่างข้อความล่าสุดไม่ได้ก็ไม่เป็นไร
    }
  }

  Future<void> send({
    required String fromUid,
    required String toUid,
    String? text,
    String? imageUrl,
    List<String> moreImageUrls = const [],
    String? videoUrl,
    Map<String, dynamic>? sharedPost,
  }) async {
    assert(
      text != null || imageUrl != null || videoUrl != null || sharedPost != null,
    );
    final ref = _db.collection('chats').doc(chatId(fromUid, toUid));
    final preview = _preview(
      text: text,
      imageUrl: imageUrl,
      moreImageUrls: moreImageUrls,
      videoUrl: videoUrl,
      sharedPost: sharedPost,
    );

    // ห้องถูกสร้างแล้วโดย ensureDirectChat; ห้ามแตะ participants (rules บังคับว่าต้องเหมือนเดิมและเรียงเดิม)
    await ensureDirectChat(fromUid, toUid);
    await ref.update({
      'lastMessage': preview,
      'lastAt': FieldValue.serverTimestamp(),
    });

    await ref.collection('messages').add({
      'senderId': fromUid,
      'text': text,
      ..._mediaFields(
        imageUrl: imageUrl,
        moreImageUrls: moreImageUrls,
        videoUrl: videoUrl,
        sharedPost: sharedPost,
      ),
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
