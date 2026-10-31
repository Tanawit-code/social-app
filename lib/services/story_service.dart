import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/story_model.dart';

class StoryService {
  final _db = FirebaseFirestore.instance;

  Stream<List<Story>> feed(String viewerId) {
    final controller = StreamController<List<Story>>();
    final userSubs = <StreamSubscription>[];
    final storySubs = <String, StreamSubscription>{};
    final storiesByAuthor = <String, List<Story>>{};
    var following = <String>{};
    var publicIds = <String>{};
    var generation = 0;

    void publish() {
      final now = Timestamp.now();
      final stories =
          storiesByAuthor.values
              .expand((items) => items)
              .where(
                (story) =>
                    story.expiresAt != null &&
                    story.expiresAt!.compareTo(now) > 0,
              )
              .toList()
            ..sort(
              (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
                a.createdAt?.millisecondsSinceEpoch ?? 0,
              ),
            );
      if (!controller.isClosed) controller.add(stories);
    }

    Future<void> refresh() async {
      final current = ++generation;
      for (final sub in storySubs.values) {
        await sub.cancel();
      }
      storySubs.clear();
      storiesByAuthor.clear();
      if (controller.isClosed || current != generation) return;
      final authors = <String>{
        viewerId,
        ...following,
        ...publicIds,
      }.where((id) => id.isNotEmpty).take(35);
      for (final authorId in authors) {
        storySubs[authorId] = _db
            .collection('stories')
            .where('authorId', isEqualTo: authorId)
            .orderBy('createdAt', descending: true)
            .limit(12)
            .snapshots()
            .listen(
              (snap) {
                storiesByAuthor[authorId] = snap.docs
                    .map(Story.fromDoc)
                    .toList();
                publish();
              },
              onError: (Object _) {
                storiesByAuthor.remove(authorId);
                publish();
              },
            );
      }
      publish();
    }

    userSubs.add(
      _db.collection('users').doc(viewerId).snapshots().listen((snap) {
        following = List<String>.from(
          snap.data()?['following'] ?? const <String>[],
        ).toSet();
        refresh();
      }, onError: controller.addError),
    );
    userSubs.add(
      _db
          .collection('users')
          .where('isPrivate', isEqualTo: false)
          .limit(35)
          .snapshots()
          .listen((snap) {
            publicIds = snap.docs.map((doc) => doc.id).toSet();
            refresh();
          }, onError: controller.addError),
    );
    controller.onCancel = () async {
      generation++;
      await Future.wait(userSubs.map((sub) => sub.cancel()));
      await Future.wait(storySubs.values.map((sub) => sub.cancel()));
    };
    return controller.stream;
  }

  Future<void> create({
    required String authorId,
    required String text,
    String? mediaUrl,
    String audience = 'public',
  }) async {
    final now = DateTime.now();
    await _db.collection('stories').add({
      'authorId': authorId,
      'text': text.trim(),
      'mediaUrl': mediaUrl,
      'audience': audience,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
    });
  }
}
