import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';

enum ProfilePostSource { personal, page, community }

/// โพสต์ที่แสดงบนโปรไฟล์ พร้อมบอกว่าโพสต์นี้อยู่ที่ไหน (ฟีดส่วนตัว / เพจ / ชุมชน)
class ProfilePost {
  final Post post;
  final ProfilePostSource source;
  final String? sourceId; // pageId หรือ communityId
  const ProfilePost(this.post, this.source, [this.sourceId]);
}

/// ดึงโพสต์สำหรับหน้าโปรไฟล์
/// - ดูโปรไฟล์ตัวเอง: เห็นทุกโพสต์ รวมโพสต์ในเพจ/ชุมชนส่วนตัว
/// - ดูโปรไฟล์คนอื่น: ซ่อนโพสต์ในเพจ/ชุมชนส่วนตัว และโพสต์ที่ผู้ดูไม่มีสิทธิ์เห็น
class ProfilePostsService {
  final _db = FirebaseFirestore.instance;

  Stream<List<ProfilePost>> stream({
    required String viewerId,
    required String targetId,
    Future<bool>? isFriend,
  }) => Stream<List<ProfilePost>>.multi((multi) {
    var closed = false;
    var pageGen = 0;
    var communityGen = 0;
    final isMe = viewerId == targetId;
    final topSubs = <StreamSubscription>[];
    final pageSubs = <StreamSubscription>[];
    final communitySubs = <StreamSubscription>[];
    final groups = <String, List<ProfilePost>>{};

    void publish() {
      if (closed) return;
      final all = groups.values.expand((e) => e).toList()
        ..sort(
          (a, b) =>
              (b.post.createdAt?.millisecondsSinceEpoch ?? 9007199254740991)
                  .compareTo(
                    a.post.createdAt?.millisecondsSinceEpoch ??
                        9007199254740991,
                  ),
        );
      multi.addSync(all);
    }

    StreamSubscription listen(
      String key,
      Query<Map<String, dynamic>> query,
      ProfilePost Function(QueryDocumentSnapshot<Map<String, dynamic>>) map, {
      bool surfaceError = false,
    }) => query.snapshots().listen(
      (snap) {
        groups[key] = snap.docs.map(map).toList();
        publish();
      },
      onError: (Object e, StackTrace s) {
        groups.remove(key);
        if (surfaceError && !closed) multi.addErrorSync(e, s);
        publish();
      },
    );

    ProfilePost personalOrPage(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final post = Post.fromDoc(d);
      return post.pageId == null
          ? ProfilePost(post, ProfilePostSource.personal)
          : ProfilePost(post, ProfilePostSource.page, post.pageId);
    }

    ProfilePost communityPost(
      String communityId,
      QueryDocumentSnapshot<Map<String, dynamic>> d,
    ) {
      final data = d.data();
      return ProfilePost(
        Post(
          id: d.id,
          authorId: data['authorId'] as String? ?? '',
          content: data['text'] as String? ?? '',
          mediaUrl: data['mediaUrl'] as String?,
          mediaType: data['mediaType'] as String?,
          moreMediaUrls: Post.urlList(data['moreMediaUrls']),
          createdAt: data['createdAt'] as Timestamp?,
          likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
          dislikeCount: (data['dislikeCount'] as num?)?.toInt() ?? 0,
        ),
        ProfilePostSource.community,
        communityId,
      );
    }

    Future<void> cancelAll(List<StreamSubscription> subs) async {
      final copy = List<StreamSubscription>.from(subs);
      subs.clear();
      await Future.wait(copy.map((s) => s.cancel()));
    }

    // เพจที่ผู้ใช้เป็นสมาชิก (คนอื่นดูได้เฉพาะเพจสาธารณะ)
    void watchPages() {
      topSubs.add(
        _db
            .collection('pages')
            .where('memberIds', arrayContains: targetId)
            .limit(20)
            .snapshots()
            .listen((snap) async {
              final gen = ++pageGen;
              await cancelAll(pageSubs);
              groups.removeWhere((k, _) => k.startsWith('page:'));
              if (closed || gen != pageGen) return;
              for (final page in snap.docs) {
                if (page.data()['privacy'] == 'private') continue;
                pageSubs.add(
                  listen(
                    'page:${page.id}',
                    _db
                        .collection('posts')
                        .where('pageId', isEqualTo: page.id)
                        .where('authorId', isEqualTo: targetId),
                    personalOrPage,
                  ),
                );
              }
              publish();
            }, onError: (Object _) {}),
      );
    }

    // ชุมชนที่ผู้ใช้เป็นสมาชิก (คนอื่นดูได้เฉพาะชุมชนสาธารณะ)
    void watchCommunities() {
      topSubs.add(
        _db
            .collection('communities')
            .orderBy('createdAt', descending: true)
            .limit(40)
            .snapshots()
            .listen((snap) async {
              final gen = ++communityGen;
              await cancelAll(communitySubs);
              groups.removeWhere((k, _) => k.startsWith('community:'));
              for (final c in snap.docs) {
                if (!isMe && c.data()['privacy'] == 'private') continue;
                try {
                  final member = await c.reference
                      .collection('members')
                      .doc(targetId)
                      .get();
                  if (!member.exists) continue;
                } catch (_) {
                  continue; // ไม่มีสิทธิ์อ่าน = ข้าม
                }
                if (closed || gen != communityGen) return;
                communitySubs.add(
                  listen(
                    'community:${c.id}',
                    c.reference
                        .collection('posts')
                        .where('authorId', isEqualTo: targetId),
                    (d) => communityPost(c.id, d),
                  ),
                );
              }
              publish();
            }, onError: (Object _) {}),
      );
    }

    Future<void> start() async {
      if (isMe) {
        topSubs.add(
          listen(
            'mine',
            _db.collection('posts').where('authorId', isEqualTo: targetId),
            personalOrPage,
            surfaceError: true,
          ),
        );
      } else {
        final friend = await (isFriend ?? Future.value(false)).catchError(
          (_) => false,
        );
        if (closed) return;
        topSubs.add(
          listen(
            'personal',
            _db
                .collection('posts')
                .where('authorId', isEqualTo: targetId)
                .where('pageId', isNull: true)
                .where(
                  'audience',
                  whereIn: friend ? ['public', 'friends'] : ['public'],
                ),
            personalOrPage,
            surfaceError: true,
          ),
        );
        watchPages();
      }
      watchCommunities();
    }

    start().catchError((Object e, StackTrace s) {
      if (!closed) multi.addErrorSync(e, s);
    });

    multi.onCancel = () async {
      closed = true;
      await cancelAll(topSubs);
      await cancelAll(pageSubs);
      await cancelAll(communitySubs);
    };
  });
}
