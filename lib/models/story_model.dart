import 'package:cloud_firestore/cloud_firestore.dart';

class Story {
  final String id;
  final String authorId;
  final String text;
  final String? mediaUrl;
  final String audience;
  final String backgroundColor;
  final Timestamp? createdAt;
  final Timestamp? expiresAt;

  const Story({
    required this.id,
    required this.authorId,
    required this.text,
    this.mediaUrl,
    this.audience = 'public',
    this.backgroundColor = '#342653',
    this.createdAt,
    this.expiresAt,
  });

  factory Story.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Story(
      id: doc.id,
      authorId: data['authorId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      mediaUrl: data['mediaUrl'] as String?,
      audience: data['audience'] as String? ?? 'public',
      backgroundColor: data['backgroundColor'] as String? ?? '#342653',
      createdAt: data['createdAt'] as Timestamp?,
      expiresAt: data['expiresAt'] as Timestamp?,
    );
  }
}
