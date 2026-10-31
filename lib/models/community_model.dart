import 'package:cloud_firestore/cloud_firestore.dart';

class Community {
  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String privacy;
  final Timestamp? createdAt;

  const Community({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.privacy,
    this.createdAt,
  });

  factory Community.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Community(
      id: doc.id,
      name: data['name'] as String? ?? 'ชุมชน',
      description: data['description'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      privacy: data['privacy'] as String? ?? 'public',
      createdAt: data['createdAt'] as Timestamp?,
    );
  }
}
