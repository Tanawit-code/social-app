import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String authorId;
  final String content;
  final String? mediaUrl;
  final String? mediaType; // 'image' | 'video' | null

  /// Extra photos of a multi-photo post. [mediaUrl] stays the first photo so
  /// older code (search, share text, reels...) keeps working and nothing is
  /// stored twice. Always empty for video posts.
  final List<String> moreMediaUrls;
  final bool isReel;
  final String? pageId;
  final String? sharedPostId;
  final String? sharedAuthorId;
  final String? sharedContent;
  final String? sharedMediaUrl;
  final String? sharedMediaType;
  final List<String> sharedMoreMediaUrls;

  /// `public`, `friends`, or `private`. Older documents default to public.
  final String audience;
  final Timestamp? createdAt;
  final int likeCount;
  final int dislikeCount;

  /// สถานะซ่อนโดยระบบดูแลโพสต์ (เขียนโดย Cloud Functions เท่านั้น)
  /// hiddenUntil == null ขณะ hidden = ซ่อนจนกว่าเจ้าของจะแก้ไข
  final bool hidden;
  final Timestamp? hiddenUntil;
  final String? hiddenBy; // 'reports' | 'admin'
  final String? hiddenReason;

  /// เจ้าของเคยแก้ไขโพสต์ที่ถูกซ่อนแล้ว แต่ระบบตรวจแล้วว่ายังไม่เพียงพอ
  final bool editRejected;

  Post({
    required this.id,
    required this.authorId,
    required this.content,
    this.mediaUrl,
    this.mediaType,
    this.moreMediaUrls = const [],
    this.isReel = false,
    this.pageId,
    this.sharedPostId,
    this.sharedAuthorId,
    this.sharedContent,
    this.sharedMediaUrl,
    this.sharedMediaType,
    this.sharedMoreMediaUrls = const [],
    this.audience = 'public',
    this.createdAt,
    this.likeCount = 0,
    this.dislikeCount = 0,
    this.hidden = false,
    this.hiddenUntil,
    this.hiddenBy,
    this.hiddenReason,
    this.editRejected = false,
  });

  /// ตอนนี้ถูกซ่อนอยู่หรือไม่ (ซ่อนแบบมีกำหนดวัน หมดเวลาแล้วถือว่าแสดงปกติ)
  bool get isHiddenNow =>
      hidden &&
      (hiddenUntil == null || hiddenUntil!.toDate().isAfter(DateTime.now()));

  /// ซ่อนจากผู้ดู [viewerUid] หรือไม่ — เจ้าของโพสต์ยังเห็นโพสต์ตัวเองเสมอ (เพื่อแก้ไข)
  bool isHiddenFor(String viewerUid) => isHiddenNow && authorId != viewerUid;

  /// Every photo of the post in display order (empty for video / text posts).
  List<String> get imageUrls => mediaUrl == null || mediaType == 'video'
      ? const []
      : [mediaUrl!, ...moreMediaUrls];

  static List<String> urlList(Object? raw) => raw is List
      ? raw.whereType<String>().where((u) => u.isNotEmpty).toList()
      : const [];

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Post(
      id: doc.id,
      authorId: data['authorId'] ?? '',
      content: data['content'] ?? '',
      mediaUrl: data['mediaUrl'],
      mediaType: data['mediaType'],
      moreMediaUrls: urlList(data['moreMediaUrls']),
      isReel: data['isReel'] == true,
      pageId: data['pageId'] as String?,
      sharedPostId: data['sharedPostId'] as String?,
      sharedAuthorId: data['sharedAuthorId'] as String?,
      sharedContent: data['sharedContent'] as String?,
      sharedMediaUrl: data['sharedMediaUrl'] as String?,
      sharedMediaType: data['sharedMediaType'] as String?,
      sharedMoreMediaUrls: urlList(data['sharedMoreMediaUrls']),
      audience: data['audience'] as String? ?? 'public',
      createdAt: data['createdAt'],
      likeCount: data['likeCount'] ?? 0,
      dislikeCount: data['dislikeCount'] ?? 0,
      hidden: data['hidden'] == true,
      hiddenUntil: data['hiddenUntil'] as Timestamp?,
      hiddenBy: data['hiddenBy'] as String?,
      hiddenReason: data['hiddenReason'] as String?,
      editRejected: data['editRejectedAt'] != null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'content': content,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      // Only written when present, so single-photo posts are unchanged.
      if (moreMediaUrls.isNotEmpty) 'moreMediaUrls': moreMediaUrls,
      'isReel': isReel,
      'pageId': pageId,
      'sharedPostId': sharedPostId,
      'sharedAuthorId': sharedAuthorId,
      'sharedContent': sharedContent,
      'sharedMediaUrl': sharedMediaUrl,
      'sharedMediaType': sharedMediaType,
      if (sharedMoreMediaUrls.isNotEmpty)
        'sharedMoreMediaUrls': sharedMoreMediaUrls,
      'audience': audience,
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': likeCount,
      'dislikeCount': dislikeCount,
    };
  }
}
