import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_model.dart';

class CommunityService {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _communities =>
      _db.collection('communities');

  Stream<List<Community>> streamCommunities() => _communities
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(Community.fromDoc).toList());

  Future<String> create({
    required String ownerId,
    required String name,
    required String description,
    required String privacy,
  }) async {
    final ref = _communities.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'name': name.trim(),
      'description': description.trim(),
      'ownerId': ownerId,
      'privacy': privacy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('members').doc(ownerId), {
      'uid': ownerId,
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return ref.id;
  }

  Future<void> join(Community community, String uid) async {
    final ref = _communities.doc(community.id);
    if (community.privacy == 'private') {
      await ref.collection('joinRequests').doc(uid).set({
        'requesterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.collection('members').doc(uid).set({
        'uid': uid,
        'role': 'member',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> cancelRequest(String communityId, String uid) => _communities
      .doc(communityId)
      .collection('joinRequests')
      .doc(uid)
      .delete();

  Future<void> approve(String communityId, String uid) async {
    final ref = _communities.doc(communityId);
    final batch = _db.batch();
    batch.set(ref.collection('members').doc(uid), {
      'uid': uid,
      'role': 'member',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(ref.collection('joinRequests').doc(uid));
    await batch.commit();
  }

  Future<void> decline(String communityId, String uid) =>
      cancelRequest(communityId, uid);

  Future<void> leave(String communityId, String uid) =>
      _communities.doc(communityId).collection('members').doc(uid).delete();

  Future<void> createPost({
    required String communityId,
    required String authorId,
    required String text,
    String? mediaUrl,
    String? mediaType,
  }) async {
    final value = text.trim();
    if ((value.isEmpty && mediaUrl == null) || value.length > 5000) {
      throw Exception(
        'โพสต์ต้องมีข้อความหรือสื่อ และข้อความต้องไม่เกิน 5,000 ตัวอักษร',
      );
    }
    if (mediaType != null && !['image', 'video'].contains(mediaType)) {
      throw Exception('ชนิดสื่อไม่ถูกต้อง');
    }
    await _communities.doc(communityId).collection('posts').add({
      'authorId': authorId,
      'text': value,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'createdAt': FieldValue.serverTimestamp(),
      'isPinned': false,
      'likeCount': 0,
      'dislikeCount': 0,
    });
  }

  DocumentReference<Map<String, dynamic>> postDocument(
    String communityId,
    String postId,
  ) => _communities.doc(communityId).collection('posts').doc(postId);

  Future<void> setReaction({
    required String communityId,
    required String postId,
    required String uid,
    required String type,
  }) async {
    final postRef = postDocument(communityId, postId);
    final reactionRef = postRef.collection('reactions').doc(uid);
    await _db.runTransaction((tx) async {
      final post = await tx.get(postRef);
      final reaction = await tx.get(reactionRef);
      final oldType = reaction.data()?['type'] as String?;
      var likes = (post.data()?['likeCount'] as num?)?.toInt() ?? 0;
      var dislikes = (post.data()?['dislikeCount'] as num?)?.toInt() ?? 0;
      if (oldType == 'like') likes--;
      if (oldType == 'dislike') dislikes--;
      if (oldType == type) {
        tx.delete(reactionRef);
      } else {
        if (type == 'like') likes++;
        if (type == 'dislike') dislikes++;
        tx.set(reactionRef, {'type': type});
      }
      tx.update(postRef, {
        'likeCount': likes < 0 ? 0 : likes,
        'dislikeCount': dislikes < 0 ? 0 : dislikes,
      });
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> comments(
    String communityId,
    String postId,
  ) => postDocument(
    communityId,
    postId,
  ).collection('comments').orderBy('createdAt').snapshots();

  Future<void> addComment({
    required String communityId,
    required String postId,
    required String authorId,
    required String text,
  }) => postDocument(communityId, postId).collection('comments').add({
    'authorId': authorId,
    'text': text.trim(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> editComment({
    required String communityId,
    required String postId,
    required String commentId,
    required String text,
  }) => postDocument(
    communityId,
    postId,
  ).collection('comments').doc(commentId).update({'text': text.trim()});

  Future<void> deleteComment({
    required String communityId,
    required String postId,
    required String commentId,
  }) => postDocument(
    communityId,
    postId,
  ).collection('comments').doc(commentId).delete();

  Future<void> editPost({
    required String communityId,
    required String postId,
    required String text,
  }) => postDocument(communityId, postId).update({'text': text.trim()});

  Future<void> deletePost(String communityId, String postId) =>
      _communities.doc(communityId).collection('posts').doc(postId).delete();

  Future<void> pinPost(String communityId, String postId, bool pinned) =>
      _communities.doc(communityId).collection('posts').doc(postId).update({
        'isPinned': pinned,
      });

  Future<void> reportPost({
    required String communityId,
    required String postId,
    required String reporterId,
    required String reason,
  }) => _communities.doc(communityId).collection('reports').add({
    'postId': postId,
    'reporterId': reporterId,
    'reason': reason,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> resolveReport(String communityId, String reportId) =>
      _communities
          .doc(communityId)
          .collection('reports')
          .doc(reportId)
          .delete();

  Future<void> banMember(String communityId, String uid) async {
    final ref = _communities.doc(communityId);
    final batch = _db.batch();
    batch.set(ref.collection('banned').doc(uid), {
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.delete(ref.collection('members').doc(uid));
    batch.delete(ref.collection('joinRequests').doc(uid));
    await batch.commit();
  }

  Future<void> unbanMember(String communityId, String uid) =>
      _communities.doc(communityId).collection('banned').doc(uid).delete();

  Future<void> setModerator(String communityId, String uid, bool moderator) =>
      _communities.doc(communityId).collection('members').doc(uid).update({
        'role': moderator ? 'moderator' : 'member',
      });
}
