import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';

class PostService {
  final CollectionReference<Map<String, dynamic>> _posts = FirebaseFirestore
      .instance
      .collection('posts');

  /// à¸ªà¸£à¹‰à¸²à¸‡à¹‚à¸žà¸ªà¸•à¹Œà¹ƒà¸«à¸¡à¹ˆ
  Future<String> createPost({
    required String authorId,
    required String content,
    String? mediaUrl,
    String? mediaType,
    String? pageId,
    String audience = 'public',
    bool isReel = false,
  }) async {
    if (pageId != null) {
      final page = await FirebaseFirestore.instance
          .collection('pages')
          .doc(pageId)
          .get();
      final members = List<String>.from(page.data()?['memberIds'] ?? const []);
      if (!page.exists || !members.contains(authorId)) {
        throw Exception(
          'à¸•à¹‰à¸­à¸‡à¹€à¸›à¹‡à¸™à¸ªà¸¡à¸²à¸Šà¸´à¸à¹€à¸žà¸ˆà¸à¹ˆà¸­à¸™à¸ˆà¸¶à¸‡à¸ˆà¸°à¹‚à¸žà¸ªà¸•à¹Œà¹„à¸”à¹‰',
        );
      }
    }
    final post = Post(
      id: '',
      authorId: authorId,
      content: content,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      isReel: isReel,
      pageId: pageId,
      audience: audience,
    );
    final doc = await _posts.add(post.toMap());
    return doc.id;
  }

  Future<String> sharePost({
    required String authorId,
    required Post original,
    required String caption,
    String audience = 'public',
  }) async {
    if (original.sharedPostId != null) {
      throw Exception('Only original posts can be reshared to the feed.');
    }
    final share = Post(
      id: '',
      authorId: authorId,
      content: caption.trim(),
      pageId: null,
      audience: audience,
      sharedPostId: original.id,
      sharedAuthorId: original.authorId,
      sharedContent: original.content,
      sharedMediaUrl: original.mediaUrl,
      sharedMediaType: original.mediaType,
    );
    final doc = await _posts.add(share.toMap());
    return doc.id;
  }

  /// à¸Ÿà¸µà¸”à¹€à¸£à¸µà¸¢à¸‡à¸•à¸²à¸¡à¹€à¸§à¸¥à¸²à¸¥à¹ˆà¸²à¸ªà¸¸à¸”à¸à¹ˆà¸­à¸™ (real-time stream)
  Stream<List<Post>> feedStream({required String viewerId, int limit = 30}) {
    final controller = StreamController<List<Post>>();
    StreamSubscription? userSub;
    StreamSubscription? blocksSub;
    StreamSubscription? friendsSub;
    StreamSubscription? publicUsersSub;
    StreamSubscription? hiddenPostsSub;
    StreamSubscription? mutedAuthorsSub;
    final postsSubs = <StreamSubscription>[];
    final byAuthor = <String, List<Post>>{};
    var following = <String>{viewerId};
    var friendIds = <String>{};
    var blocked = <String>{};
    var publicAuthors = <String>{};
    var hiddenPostIds = <String>{};
    var mutedAuthorIds = <String>{};
    var refreshNumber = 0;

    void publish(
      String authorId,
      String source,
      QuerySnapshot<Map<String, dynamic>> snap,
    ) {
      byAuthor['$authorId:$source'] = snap.docs.map(Post.fromDoc).toList();
      if (!controller.isClosed) {
        final combined = byAuthor.values.expand((posts) => posts).toList()
          ..sort(
            (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
              a.createdAt?.millisecondsSinceEpoch ?? 0,
            ),
          );
        final ids = <String>{};
        controller.add(
          combined
              .where(
                (post) =>
                    !hiddenPostIds.contains(post.id) &&
                    !mutedAuthorIds.contains(post.authorId) &&
                    ids.add(post.id),
              )
              .take(limit)
              .toList(),
        );
      }
    }

    void handleError(Object error, StackTrace stack) {
      // Rules deny listeners for accounts that blocked this viewer.
      if (!error.toString().contains('permission-denied') &&
          !controller.isClosed) {
        controller.addError(error, stack);
      }
    }

    Future<void> refresh() async {
      final refreshId = ++refreshNumber;
      final previous = List<StreamSubscription>.from(postsSubs);
      postsSubs.clear();
      byAuthor.clear();
      await Future.wait(previous.map((sub) => sub.cancel()));
      if (controller.isClosed || refreshId != refreshNumber) return;
      final followedAuthors = following
          .where(
            (id) =>
                id.isNotEmpty &&
                !blocked.contains(id) &&
                !mutedAuthorIds.contains(id),
          )
          .toSet();
      final visibleFriends = friendIds.where(
        (id) => !blocked.contains(id) && !mutedAuthorIds.contains(id),
      );
      final authors = <String>{viewerId, ...followedAuthors, ...visibleFriends};
      authors.addAll(
        publicAuthors.where(
          (id) => !blocked.contains(id) && !mutedAuthorIds.contains(id),
        ),
      );
      final orderedAuthors = authors.take(30).toList();
      if (orderedAuthors.isEmpty) {
        if (!controller.isClosed) controller.add(const []);
        return;
      }
      for (final authorId in orderedAuthors) {
        if (authorId == viewerId) {
          final sub = _posts
              .where('authorId', isEqualTo: authorId)
              .where('pageId', isNull: true)
              .orderBy('createdAt', descending: true)
              .limit(limit)
              .snapshots()
              .listen(
                (snap) => publish(authorId, 'all', snap),
                onError: handleError,
              );
          postsSubs.add(sub);
          continue;
        }

        var isFriend = friendIds.contains(authorId);
        if (!isFriend && followedAuthors.contains(authorId)) {
          try {
            final friendship = await FirebaseFirestore.instance
                .collection('users')
                .doc(viewerId)
                .collection('friends')
                .doc(authorId)
                .get();
            isFriend = friendship.exists;
            if (!isFriend) {
              final author = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(authorId)
                  .get();
              isFriend = List<String>.from(
                author.data()?['followers'] ?? const [],
              ).contains(viewerId);
            }
          } catch (_) {
            // A blocked or private account may be unavailable; its public posts
            // can still be queried if Firestore Rules allow them.
          }
          if (controller.isClosed || refreshId != refreshNumber) return;
        }
        final audiences = isFriend
            ? <String>['public', 'friends']
            : <String>['public'];
        final sub = _posts
            .where('authorId', isEqualTo: authorId)
            .where('pageId', isNull: true)
            .where('audience', whereIn: audiences)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .listen(
              (snap) => publish(authorId, 'visible', snap),
              onError: handleError,
            );
        postsSubs.add(sub);
      }
    }

    userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(viewerId)
        .snapshots()
        .listen(
          (snap) {
            following = {
              viewerId,
              ...List<String>.from(snap.data()?['following'] ?? const []),
            };
            refresh();
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          },
        );
    blocksSub = FirebaseFirestore.instance
        .collection('users')
        .doc(viewerId)
        .collection('blocks')
        .snapshots()
        .listen(
          (snap) {
            blocked = snap.docs.map((doc) => doc.id).toSet();
            refresh();
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          },
        );
    friendsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(viewerId)
        .collection('friends')
        .snapshots()
        .listen(
          (snap) {
            friendIds = snap.docs.map((doc) => doc.id).toSet();
            refresh();
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          },
        );
    publicUsersSub = FirebaseFirestore.instance
        .collection('users')
        .where('isPrivate', isEqualTo: false)
        .limit(200)
        .snapshots()
        .listen(
          (snap) {
            publicAuthors = snap.docs.map((doc) => doc.id).toSet();
            refresh();
          },
          onError: (Object error, StackTrace stack) {
            // Keep followed accounts available even if public profile discovery fails.
            if (!controller.isClosed &&
                !error.toString().contains('permission-denied')) {
              controller.addError(error, stack);
            }
          },
        );
    hiddenPostsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(viewerId)
        .collection('hiddenPosts')
        .snapshots()
        .listen(
          (snap) {
            hiddenPostIds = snap.docs.map((doc) => doc.id).toSet();
            refresh();
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          },
        );
    mutedAuthorsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(viewerId)
        .collection('mutedAuthors')
        .snapshots()
        .listen(
          (snap) {
            mutedAuthorIds = snap.docs.map((doc) => doc.id).toSet();
            refresh();
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          },
        );
    controller.onCancel = () async {
      await userSub?.cancel();
      await blocksSub?.cancel();
      await friendsSub?.cancel();
      await publicUsersSub?.cancel();
      await hiddenPostsSub?.cancel();
      await mutedAuthorsSub?.cancel();
      await Future.wait(postsSubs.map((sub) => sub.cancel()));
    };
    return controller.stream;
  }

  /// à¹à¸à¹‰à¹„à¸‚à¹‚à¸žà¸ªà¸•à¹Œ (à¹€à¸‰à¸žà¸²à¸°à¹€à¸ˆà¹‰à¸²à¸‚à¸­à¸‡ - à¹€à¸Šà¹‡à¸„à¸ªà¸´à¸—à¸˜à¸´à¹Œà¸—à¸µà¹ˆ Firestore rules à¸”à¹‰à¸§à¸¢)
  Future<void> updatePost(
    String postId,
    String newContent, {
    String? audience,
  }) {
    return _posts.doc(postId).update({
      'content': newContent,
      if (audience != null) 'audience': audience,
    });
  }

  /// à¸¥à¸šà¹‚à¸žà¸ªà¸•à¹Œ
  Future<void> deletePost(String postId) {
    return _posts.doc(postId).delete();
  }

  Future<void> hidePost(String viewerId, String postId) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(viewerId)
        .collection('hiddenPosts')
        .doc(postId);
    if (!(await ref.get()).exists)
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> unhidePost(String viewerId, String postId) => FirebaseFirestore
      .instance
      .collection('users')
      .doc(viewerId)
      .collection('hiddenPosts')
      .doc(postId)
      .delete();

  Future<void> muteAuthor(String viewerId, String authorId) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(viewerId)
        .collection('mutedAuthors')
        .doc(authorId);
    if (!(await ref.get()).exists)
      await ref.set({'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> unmuteAuthor(String viewerId, String authorId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(viewerId)
          .collection('mutedAuthors')
          .doc(authorId)
          .delete();

  /// like / dislike / emoji reaction (à¹€à¸à¹‡à¸š 1 reaction à¸•à¹ˆà¸­ 1 user à¸•à¹ˆà¸­à¹‚à¸žà¸ªà¸•à¹Œ)
  Stream<QuerySnapshot<Map<String, dynamic>>> reactionsStream(String postId) =>
      _posts.doc(postId).collection('reactions').snapshots();

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

  /// à¸„à¸­à¸¡à¹€à¸¡à¸™à¸•à¹Œ
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

  Future<void> updateComment({
    required String postId,
    required String commentId,
    required String text,
  }) => _posts.doc(postId).collection('comments').doc(commentId).update({
    'text': text,
  });

  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) => _posts.doc(postId).collection('comments').doc(commentId).delete();

  /// à¸£à¸²à¸¢à¸‡à¸²à¸™à¹‚à¸žà¸ªà¸•à¹Œ
  Future<void> reportPost({
    required String postId,
    required String reporterId,
    required String reason,
  }) {
    return reportTarget(
      targetType: 'post',
      targetId: postId,
      reporterId: reporterId,
      reason: reason,
    );
  }

  Future<void> reportTarget({
    required String targetType,
    required String targetId,
    required String reporterId,
    required String reason,
    String details = '',
  }) {
    return FirebaseFirestore.instance.collection('reports').add({
      'targetType': targetType,
      'targetId': targetId,
      'reporterId': reporterId,
      'reason': reason,
      'details': details,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
