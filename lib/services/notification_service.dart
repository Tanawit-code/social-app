import 'package:cloud_firestore/cloud_firestore.dart';

/// ชนิดของแจ้งเตือน — ใช้ค่าเหล่านี้แทนการพิมพ์ string เอง
class NotifType {
  static const like = 'like';
  static const comment = 'comment';
  static const message = 'message';
  static const follow = 'follow';
  static const followRequest = 'follow_request';
  static const friendRequest = 'friend_request';
  static const friendAccepted = 'friend_accepted';
  static const communityJoinRequest = 'community_join_request';
  static const communityJoinApproved = 'community_join_approved';
  static const communityJoinDeclined = 'community_join_declined';
  static const pageJoinRequest = 'page_join_request';
  static const pageJoinApproved = 'page_join_approved';
  static const pageJoinDeclined = 'page_join_declined';
}

/// "มาจากระบบไหน" ของแจ้งเตือน — เก็บในฟิลด์ source
class NotifSource {
  static const post = 'post';
  static const friend = 'friend';
  static const follow = 'follow';
  static const chat = 'chat';
  static const community = 'community';
  static const page = 'page';

  /// เดา source จาก type (ใช้กับแจ้งเตือนเก่าที่ยังไม่มีฟิลด์ source)
  static String fromType(String type) {
    switch (type) {
      case NotifType.like:
      case NotifType.comment:
        return post;
      case NotifType.message:
        return chat;
      case NotifType.follow:
      case NotifType.followRequest:
        return follow;
      case NotifType.friendRequest:
      case NotifType.friendAccepted:
        return friend;
      case NotifType.communityJoinRequest:
      case NotifType.communityJoinApproved:
      case NotifType.communityJoinDeclined:
        return community;
      case NotifType.pageJoinRequest:
      case NotifType.pageJoinApproved:
      case NotifType.pageJoinDeclined:
        return page;
      default:
        return post;
    }
  }
}

/// แจ้งเตือนแบบ in-app เก็บที่ users/{uid}/notifications
/// ทุกแจ้งเตือนมี type (เกิดอะไรขึ้น) และ source (มาจากระบบไหน)
/// source = 'post' | 'friend' | 'follow' | 'chat' | 'community' | 'page'
/// sourceId / sourceName = id และชื่อของชุมชน/เพจต้นทาง (ถ้ามี)
class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('notifications');

  Future<void> create({
    required String toUid,
    required String fromUid,
    required String type,
    String? postId,
    String? text,
    String? groupId,
    String? groupName,
    String? chatId,
    String? source,
    String? sourceId,
    String? sourceName,
  }) async {
    if (toUid.isEmpty || toUid == fromUid) return; // ไม่แจ้งเตือนตัวเอง
    await _col(toUid).add({
      'fromUid': fromUid,
      'type': type,
      'source': source ?? NotifSource.fromType(type),
      'sourceId': sourceId,
      'sourceName': sourceName,
      'postId': postId,
      'text': text,
      'groupId': groupId,
      'groupName': groupName,
      'chatId': chatId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> stream(String uid) {
    return _col(
      uid,
    ).orderBy('createdAt', descending: true).limit(50).snapshots();
  }

  /// จำนวนที่ยังไม่อ่าน แยกเป็น 2 กลุ่ม
  /// messages: true  = แจ้งเตือนข้อความแชท (แสดงที่ไอคอนแชท)
  /// messages: false = อย่างอื่น เช่น ติดตาม/ไลก์/คอมเมนต์ (แสดงที่ไอคอนกระดิ่ง)
  /// นับฝั่ง client จาก query เดียว จึงไม่ต้องสร้าง index เพิ่มใน Firestore
  Stream<int> unreadCount(String uid, {required bool messages}) {
    return _col(uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map(
          (s) => s.docs
              .where((d) => (d.data()['type'] == 'message') == messages)
              .length,
        );
  }

  Stream<int> groupUnreadCount(String uid, String groupId) {
    return _col(uid)
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.where((doc) => doc.data()['isRead'] != true).length,
        );
  }

  Stream<int> chatUnreadCount(String uid, String chatId) {
    return _col(uid)
        .where('chatId', isEqualTo: chatId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.where((doc) => doc.data()['isRead'] != true).length,
        );
  }

  Future<void> markGroupRead(String uid, String groupId) async {
    final snap = await _col(uid).where('groupId', isEqualTo: groupId).get();
    final unread = snap.docs
        .where((doc) => doc.data()['isRead'] != true)
        .toList();
    for (var i = 0; i < unread.length; i += 450) {
      final batch = _db.batch();
      for (final doc in unread.skip(i).take(450)) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }
  }

  Future<void> markChatRead(String uid, String chatId) async {
    final snap = await _col(uid).where('chatId', isEqualTo: chatId).get();
    final unread = snap.docs
        .where((doc) => doc.data()['isRead'] != true)
        .toList();
    for (var i = 0; i < unread.length; i += 450) {
      final batch = _db.batch();
      for (final doc in unread.skip(i).take(450)) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }
  }

  /// ทำเครื่องหมายอ่านแล้วเฉพาะกลุ่ม (ข้อความแชท หรือ อย่างอื่น)
  Future<void> markRead(String uid, {required bool messages}) async {
    final snap = await _col(uid).where('isRead', isEqualTo: false).get();
    final targets = snap.docs
        .where((d) => (d.data()['type'] == 'message') == messages)
        .toList();
    if (targets.isEmpty) return;
    final batch = _db.batch();
    for (final d in targets) {
      batch.update(d.reference, {'isRead': true});
    }
    await batch.commit();
  }
}
