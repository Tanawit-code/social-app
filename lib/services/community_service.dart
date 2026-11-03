import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_model.dart';
import '../utils/mention.dart';
import 'mention_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

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


  Future<void> updateBrand({
    required String communityId,
    required String ownerId,
    required String coverUrl,
    required String themeColor,
  }) async {
    final ref = _communities.doc(communityId);
    final snap = await ref.get();
    if (!snap.exists || snap.data()?['ownerId'] != ownerId) {
      throw Exception('เฉพาะเจ้าของชุมชนเท่านั้นที่ตกแต่งได้');
    }
    await ref.update({'coverUrl': coverUrl, 'themeColor': themeColor});
  }

  Future<void> join(Community community, String uid) async {
    final ref = _communities.doc(community.id);
    if (community.privacy == 'private') {
      await ref.collection('joinRequests').doc(uid).set({
        'requesterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _notify(
        community,
        toUid: community.ownerId,
        fromUid: uid,
        type: NotifType.communityJoinRequest,
      );
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

  /// แจ้งเตือนที่ผูกกับชุมชน — ความล้มเหลวของแจ้งเตือนต้องไม่ทำให้ action หลักล้มเหลว
  Future<void> _notify(
    Community community, {
    required String toUid,
    required String fromUid,
    required String type,
    String? postId,
    String? text,
  }) async {
    try {
      await NotificationService().create(
        toUid: toUid,
        fromUid: fromUid,
        type: type,
        postId: postId,
        text: text,
        source: NotifSource.community,
        sourceId: community.id,
        sourceName: community.name,
      );
    } catch (_) {}
  }

  Future<void> approve(
    Community community,
    String uid, {
    required String byUid,
  }) async {
    final communityId = community.id;
    final ref = _communities.doc(communityId);
    final batch = _db.batch();
    batch.set(ref.collection('members').doc(uid), {
      'uid': uid,
      'role': 'member',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(ref.collection('joinRequests').doc(uid));
    await batch.commit();
    await _notify(
      community,
      toUid: uid,
      fromUid: byUid,
      type: NotifType.communityJoinApproved,
    );
  }

  Future<void> decline(
    Community community,
    String uid, {
    required String byUid,
  }) async {
    await cancelRequest(community.id, uid);
    await _notify(
      community,
      toUid: uid,
      fromUid: byUid,
      type: NotifType.communityJoinDeclined,
    );
  }

  Future<void> leave(String communityId, String uid) =>
      _communities.doc(communityId).collection('members').doc(uid).delete();

  Future<String> createPost({
    required String communityId,
    required String authorId,
    required String text,
    String? mediaUrl,
    String? mediaType,
    List<String> moreMediaUrls = const [],
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
    if (moreMediaUrls.isNotEmpty &&
        (mediaType != 'image' ||
            mediaUrl == null ||
            moreMediaUrls.length >= StorageService.maxPostImages)) {
      throw Exception(
        'เลือกรูปได้ไม่เกิน ${StorageService.maxPostImages} รูปต่อโพสต์',
      );
    }
    final ref = await _communities.doc(communityId).collection('posts').add({
      'authorId': authorId,
      'text': value,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      if (moreMediaUrls.isNotEmpty) 'moreMediaUrls': moreMediaUrls,
      'createdAt': FieldValue.serverTimestamp(),
      'isPinned': false,
      'likeCount': 0,
      'dislikeCount': 0,
    });
    await _notifyMentions(
      communityId: communityId,
      postId: ref.id,
      text: value,
      fromUid: authorId,
      inComment: false,
    );
    return ref.id;
  }

  /// แจ้งเตือนคนที่ถูกแท็กในโพสต์/คอมเมนต์ของชุมชน — [skip] = คนที่เคยถูกแท็กไว้แล้ว (ตอนแก้ไข)
  /// [excludePostAuthor] ใช้ตอนคอมเมนต์ใหม่ เพราะเจ้าของโพสต์ได้แจ้งเตือน "คอมเมนต์" ไปแล้ว
  Future<void> _notifyMentions({
    required String communityId,
    required String postId,
    required String text,
    required String fromUid,
    required bool inComment,
    Set<String> skip = const {},
    bool excludePostAuthor = false,
  }) async {
    if (Mention.uids(text).isEmpty) return;
    try {
      final community = await _communities.doc(communityId).get();
      final exclude = <String>{};
      if (excludePostAuthor) {
        final post = await postDocument(communityId, postId).get();
        final author = post.data()?['authorId'] as String?;
        if (author != null) exclude.add(author);
      }
      await MentionService.notify(
        text: text,
        fromUid: fromUid,
        inComment: inComment,
        postId: postId,
        source: NotifSource.community,
        sourceId: communityId,
        sourceName: community.data()?['name'] as String?,
        skip: skip,
        exclude: exclude,
      );
    } catch (_) {}
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
    const allowed = [
      'like',
      'dislike',
      'love',
      'care',
      'haha',
      'wow',
      'sad',
      'angry',
    ];
    if (!allowed.contains(type)) throw Exception('ชนิด reaction ไม่ถูกต้อง');
    final postRef = postDocument(communityId, postId);
    final reactionRef = postRef.collection('reactions').doc(uid);
    var added = false;
    await _db.runTransaction((tx) async {
      final post = await tx.get(postRef);
      final reaction = await tx.get(reactionRef);
      final oldType = reaction.data()?['type'] as String?;
      added = oldType != type;
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
    if (added && type != 'dislike') {
      await _notifyPostActivity(
        communityId: communityId,
        postId: postId,
        fromUid: uid,
        type: NotifType.like,
      );
    }
  }

  /// แจ้งเจ้าของโพสต์ในชุมชนเมื่อมีคนกดถูกใจ/คอมเมนต์ (อ่านชื่อชุมชนและเจ้าของโพสต์เอง)
  Future<void> _notifyPostActivity({
    required String communityId,
    required String postId,
    required String fromUid,
    required String type,
    String? text,
  }) async {
    try {
      final results = await Future.wait([
        postDocument(communityId, postId).get(),
        _communities.doc(communityId).get(),
      ]);
      final authorId = results[0].data()?['authorId'] as String? ?? '';
      await NotificationService().create(
        toUid: authorId,
        fromUid: fromUid,
        type: type,
        postId: postId,
        text: text,
        source: NotifSource.community,
        sourceId: communityId,
        sourceName: results[1].data()?['name'] as String?,
      );
    } catch (_) {}
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> reactions(
    String communityId,
    String postId,
  ) => postDocument(communityId, postId).collection('reactions').snapshots();

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
  }) async {
    final value = text.trim();
    await postDocument(communityId, postId).collection('comments').add({
      'authorId': authorId,
      'text': value,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _notifyPostActivity(
      communityId: communityId,
      postId: postId,
      fromUid: authorId,
      type: NotifType.comment,
      text: Mention.plain(value).length > 80
          ? Mention.plain(value).substring(0, 80)
          : Mention.plain(value),
    );
    await _notifyMentions(
      communityId: communityId,
      postId: postId,
      text: value,
      fromUid: authorId,
      inComment: true,
      excludePostAuthor: true,
    );
  }

  Future<void> editComment({
    required String communityId,
    required String postId,
    required String commentId,
    required String text,
  }) async {
    final ref = postDocument(
      communityId,
      postId,
    ).collection('comments').doc(commentId);
    Map<String, dynamic>? old;
    try {
      old = (await ref.get()).data();
    } catch (_) {}
    await ref.update({'text': text.trim()});
    if (old == null) return;
    await _notifyMentions(
      communityId: communityId,
      postId: postId,
      text: text.trim(),
      fromUid: old['authorId'] as String? ?? '',
      inComment: true,
      skip: Mention.uids(old['text'] as String?),
    );
  }

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
  }) async {
    final ref = postDocument(communityId, postId);
    Map<String, dynamic>? old;
    try {
      old = (await ref.get()).data();
    } catch (_) {}
    await ref.update({'text': text.trim()});
    if (old == null) return;
    await _notifyMentions(
      communityId: communityId,
      postId: postId,
      text: text.trim(),
      fromUid: old['authorId'] as String? ?? '',
      inComment: false,
      skip: Mention.uids(old['text'] as String?),
    );
  }

  Future<void> deletePost(String communityId, String postId) =>
      _communities.doc(communityId).collection('posts').doc(postId).delete();

  Future<void> pinPost(String communityId, String postId, bool pinned) =>
      _communities.doc(communityId).collection('posts').doc(postId).update({
        'isPinned': pinned,
      });

  /// รายงานโพสต์ (หรือคอมเมนต์ใต้โพสต์เมื่อใส่ [commentId]) ถึงผู้ดูแลชุมชน
  /// id ของรายงาน = {reporter}_{postId}[_{commentId}] จึงรายงานซ้ำไม่ได้ (rules บังคับ)
  Future<void> reportContent({
    required String communityId,
    required String postId,
    String? commentId,
    required String reporterId,
    required String reason,
    String details = '',
    String reportedUid = '',
  }) => _communities
      .doc(communityId)
      .collection('reports')
      .doc('${reporterId}_$postId${commentId == null ? '' : '_$commentId'}')
      .set({
        'postId': postId,
        'targetType': commentId == null ? 'post' : 'comment',
        if (commentId != null) 'commentId': commentId,
        'reporterId': reporterId,
        'reportedUid': reportedUid,
        'reason': reason,
        'details': details,
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// ผู้ดูแลลบเนื้อหาที่ถูกรายงาน แล้วปิดรายงานนั้น
  Future<void> removeReportedContent(
    String communityId,
    String reportId,
    Map<String, dynamic> report,
  ) async {
    final postId = report['postId'] as String? ?? '';
    final commentId = report['commentId'] as String?;
    if (commentId != null) {
      await deleteComment(
        communityId: communityId,
        postId: postId,
        commentId: commentId,
      );
    } else {
      await deletePost(communityId, postId);
    }
    await resolveReport(communityId, reportId);
  }

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

  /// ลบชุมชนถาวร (เฉพาะเจ้าของ) — ลบลูกทั้งหมดก่อน (คอมเมนต์/รีแอคชันของโพสต์, โพสต์,
  /// คำขอเข้าร่วม, รายการแบน, รายงาน, สมาชิกอื่น) แล้วลบสมาชิกเจ้าของพร้อมตัวชุมชนใน batch เดียว
  /// ถ้าล้มเหลวกลางทางชุมชนยังอยู่ และกดลบซ้ำได้
  Future<void> deleteCommunity(String communityId, String ownerId) async {
    final ref = _communities.doc(communityId);
    final snap = await ref.get();
    if (!snap.exists) return;
    if (snap.data()?['ownerId'] != ownerId) {
      throw Exception('เฉพาะเจ้าของชุมชนเท่านั้นที่ลบชุมชนได้');
    }
    final posts = await ref.collection('posts').get();
    for (final post in posts.docs) {
      final comments = await post.reference.collection('comments').get();
      final reactions = await post.reference.collection('reactions').get();
      await _deleteInChunks([
        ...comments.docs.map((d) => d.reference),
        ...reactions.docs.map((d) => d.reference),
      ]);
    }
    await _deleteInChunks(posts.docs.map((d) => d.reference).toList());
    for (final name in ['joinRequests', 'banned', 'reports']) {
      final docs = await ref.collection(name).get();
      await _deleteInChunks(docs.docs.map((d) => d.reference).toList());
    }
    final members = await ref.collection('members').get();
    await _deleteInChunks(
      members.docs
          .where((d) => d.id != ownerId)
          .map((d) => d.reference)
          .toList(),
    );
    final last = _db.batch();
    last.delete(ref.collection('members').doc(ownerId));
    last.delete(ref);
    await last.commit();
  }

  Future<void> _deleteInChunks(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final r in refs.skip(i).take(400)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }
}
