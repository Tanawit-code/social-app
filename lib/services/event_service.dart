import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event_model.dart';

class EventService {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _events =>
      _db.collection('events');

  Stream<List<SocialEvent>> stream() => _events
      .orderBy('startAt')
      .snapshots()
      .map((snap) => snap.docs.map(SocialEvent.fromDoc).toList());

  Future<String> create({
    required String hostId,
    required String name,
    required String description,
    required String location,
    required DateTime startAt,
  }) async {
    final ref = await _events.add({
      'hostId': hostId,
      'name': name.trim(),
      'description': description.trim(),
      'location': location.trim(),
      'startAt': Timestamp.fromDate(startAt),
      'isCancelled': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setResponse({
    required String eventId,
    required String uid,
    required String? status,
  }) async {
    final ref = _events.doc(eventId).collection('responses').doc(uid);
    if (status == null) {
      await ref.delete();
    } else {
      await ref.set({
        'uid': uid,
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> responses(String eventId) =>
      _events.doc(eventId).collection('responses').snapshots();
  Future<void> delete(String eventId) =>
      _events.doc(eventId).update({'isCancelled': true});
}
