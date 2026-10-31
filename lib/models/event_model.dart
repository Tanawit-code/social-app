import 'package:cloud_firestore/cloud_firestore.dart';

class SocialEvent {
  final String id;
  final String name;
  final String description;
  final String hostId;
  final String location;
  final Timestamp startAt;
  final bool isCancelled;

  const SocialEvent({
    required this.id,
    required this.name,
    required this.description,
    required this.hostId,
    required this.location,
    required this.startAt,
    this.isCancelled = false,
  });

  factory SocialEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return SocialEvent(
      id: doc.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      hostId: data['hostId'] as String? ?? '',
      location: data['location'] as String? ?? '',
      startAt: data['startAt'] as Timestamp? ?? Timestamp.now(),
      isCancelled: data['isCancelled'] == true,
    );
  }
}
