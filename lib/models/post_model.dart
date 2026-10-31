import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String authorId;
  final String content;
  final String? mediaUrl;
  final String? mediaType; // 'image' | 'video' | null
  final bool isReel;
  final String? pageId;
  final String? sharedPostId;
  final String? sharedAuthorId;
  final String? sharedContent;
  final String? sharedMediaUrl;
  final String? sharedMediaType;

  /// `public`, `friends`, or `private`. Older documents default to public.
  final String audience;
  final Timestamp? createdAt;
  final int likeCount;
  final int dislikeCount;

  Post({
    required this.id,
    required this.authorId,
    required this.content,
    this.mediaUrl,
    this.mediaType,
    this.isReel = false,
    this.pageId,
    this.sharedPostId,
    this.sharedAuthorId,
    this.sharedContent,
    this.sharedMediaUrl,
    this.sharedMediaType,
    this.audience = 'public',
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
      isReel: data['isReel'] == true,
      pageId: data['pageId'] as String?,
      sharedPostId: data['sharedPostId'] as String?,
      sharedAuthorId: data['sharedAuthorId'] as String?,
      sharedContent: data['sharedContent'] as String?,
      sharedMediaUrl: data['sharedMediaUrl'] as String?,
      sharedMediaType: data['sharedMediaType'] as String?,
      audience: data['audience'] as String? ?? 'public',
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
      'isReel': isReel,
      'pageId': pageId,
      'sharedPostId': sharedPostId,
      'sharedAuthorId': sharedAuthorId,
      'sharedContent': sharedContent,
      'sharedMediaUrl': sharedMediaUrl,
      'sharedMediaType': sharedMediaType,
      'audience': audience,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': likeCount,
      'dislikeCount': dislikeCount,
    };
  }
}
