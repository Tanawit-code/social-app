import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String authorId;
  final String content;
  final String? mediaUrl;
  final String? mediaType; // 'image' | 'video' | null
  final String? pageId;
  final Timestamp? createdAt;
  final int likeCount;
  final int dislikeCount;

  Post({
    required this.id,
    required this.authorId,
    required this.content,
    this.mediaUrl,
    this.mediaType,
    this.pageId,
    this.createdAt,
    this.likeCount = 0,
    this.dislikeCount = 0,
  });

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Post(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      content: data['content'] ?? '',
      mediaUrl: data['mediaUrl'],
      mediaType: data['mediaType'],
      pageId: data['pageId'] as String?,
      createdAt: data['createdAt'],
      likeCount: data['likeCount'] ?? 0,
      dislikeCount: data['dislikeCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'content': content,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'pageId': pageId,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': likeCount,
      'dislikeCount': dislikeCount,
    };
  }
}
