import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';

class PostService {
  final CollectionReference<Map<String, dynamic>> _posts = FirebaseFirestore
      .instance
      .collection('posts');

  /// สร้างโพสต์ใหม่
  Future<String> createPost({
    required String authorId,
    required String content,
    String? mediaUrl,
    String? mediaType,
  }) async {
    final post = Post(
      id: '',
      authorId: authorId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
    );
    final doc = await _posts.add(post.toMap());
    return doc.id;
  }

  /// ฟีดเรียงตามเวลาล่าสุดก่อน (real-time stream)
  Stream<List<Post>> feedStream({int limit = 30}) {
    return _posts
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Post.fromDoc(d)).toList());
  }

  /// แก้ไขโพสต์ (เฉพาะเจ้าของ - เช็คสิทธิ์ที่ Firestore rules ด้วย)
  Future<void> updatePost(String postId, String newContent) {
    return _posts.doc(postId).update({'content': newContent});
  }

  /// ลบโพสต์
  Future<void> deletePost(String postId) {
    return _posts.doc(postId).delete();
  }

  /// like / dislike / emoji reaction (เก็บ 1 reaction ต่อ 1 user ต่อโพสต์)
  Future<void> setReaction({
    required String postId,
    required String uid,
    required String type, // 'like' | 'dislike' | emoji code
  }) async {
    final reactionRef = _posts.doc(postId).collection('reactions').doc(uid);
    final existing = await reactionRef.get();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final postSnap = await tx.get(_posts.doc(postId));
      int likeCount = postSnap['likeCount'] ?? 0;
      int dislikeCount = postSnap['dislikeCount'] ?? 0;

      if (existing.exists) {
        final oldType = existing['type'];
        if (oldType == 'like') likeCount--;
        if (oldType == 'dislike') dislikeCount--;
      }
      if (type == 'like') likeCount++;
      if (type == 'dislike') dislikeCount++;

      tx.set(reactionRef, {'type': type});
      tx.update(_posts.doc(postId), {
        'likeCount': likeCount,
        'dislikeCount': dislikeCount,
      });
    });
  }

  /// คอมเมนต์
  Future<void> addComment({
    required String postId,
    required String authorId,
    required String text,
  }) {
    return _posts.doc(postId).collection('comments').add({
      'authorId': authorId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> commentsStream(String postId) {
    return _posts
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots();
  }

  /// รายงานโพสต์
  Future<void> reportPost({
    required String postId,
    required String reporterId,
    required String reason,
  }) {
    return FirebaseFirestore.instance.collection('reports').add({
      'postId': postId,
      'reporterId': reporterId,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
