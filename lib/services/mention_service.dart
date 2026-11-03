import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../utils/mention.dart';
import 'notification_service.dart';

class MentionUser {
  final String uid;
  final String name;
  const MentionUser(this.uid, this.name);
}

/// ขอบเขตว่า "แท็กใครได้" ในที่ที่กำลังพิมพ์
/// - สาธารณะ  → แท็กได้ทุกคน
/// - เพจ/ชุมชนส่วนตัว → แท็กได้เฉพาะสมาชิก
/// - โพสต์เฉพาะเพื่อน → แท็กได้เฉพาะเพื่อนของเจ้าของโพสต์
/// - โพสต์ส่วนตัว → แท็กไม่ได้
class MentionScope {
  final Future<List<MentionUser>> Function()? _loader;
  Future<List<MentionUser>>? _memo;
  MentionScope._(this._loader);

  static final MentionScope none = MentionScope._(null);

  bool get enabled => _loader != null;

  static final _db = FirebaseFirestore.instance;

  factory MentionScope.everyone(String me) =>
      MentionScope._(() => MentionDirectory.all(me));

  factory MentionScope.uids(String me, Future<List<String>> Function() ids) =>
      MentionScope._(() async => MentionDirectory.byIds(await ids(), me));

  factory MentionScope.friends(String me) => MentionScope.uids(me, () async {
    final snap = await _db
        .collection('users')
        .doc(me)
        .collection('friends')
        .get();
    return snap.docs.map((d) => d.id).toList();
  });

  /// เพจสาธารณะ = ทุกคน (ยกเว้นคนที่ถูกแบน), เพจส่วนตัว = สมาชิกเท่านั้น
  factory MentionScope.page(String pageId, String me) => MentionScope._(() async {
    final data = (await _db.collection('pages').doc(pageId).get()).data();
    if (data == null) return <MentionUser>[];
    final banned = List<String>.from(data['bannedIds'] ?? const []).toSet();
    if (data['privacy'] == 'public') {
      final all = await MentionDirectory.all(me);
      return all.where((u) => !banned.contains(u.uid)).toList();
    }
    final members = List<String>.from(data['memberIds'] ?? const [])
        .where((id) => !banned.contains(id))
        .toList();
    return MentionDirectory.byIds(members, me);
  });

  /// ชุมชนสาธารณะ = ทุกคน, ชุมชนส่วนตัว = สมาชิกเท่านั้น
  factory MentionScope.community(String communityId, String me) =>
      MentionScope._(() async {
        final ref = _db.collection('communities').doc(communityId);
        final data = (await ref.get()).data();
        if (data == null) return <MentionUser>[];
        if ((data['privacy'] ?? 'public') == 'public') {
          return MentionDirectory.all(me);
        }
        final members = await ref.collection('members').get();
        return MentionDirectory.byIds(members.docs.map((d) => d.id).toList(), me);
      });

  factory MentionScope.audience(String audience, String me) {
    switch (audience) {
      case 'public':
        return MentionScope.everyone(me);
      case 'friends':
        return MentionScope.friends(me);
      default:
        return MentionScope.none;
    }
  }

  /// ขอบเขตของโพสต์ที่มีอยู่แล้ว (ใช้กับช่องคอมเมนต์)
  factory MentionScope.post(Post post, String me) {
    if (post.pageId != null) return MentionScope.page(post.pageId!, me);
    if (post.audience == 'friends' && post.authorId != me) {
      // อ่านรายชื่อเพื่อนของเจ้าของโพสต์ไม่ได้ จึงไม่รู้ว่าใครมีสิทธิ์ดูโพสต์นี้
      return MentionScope.none;
    }
    return MentionScope.audience(post.audience, me);
  }

  Future<List<MentionUser>> search(String query) async {
    final loader = _loader;
    if (loader == null) return const [];
    final all = await (_memo ??= loader());
    final q = query.trim().toLowerCase();
    final hits = all
        .where((u) => q.isEmpty || u.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final as = a.name.toLowerCase().startsWith(q) ? 0 : 1;
        final bs = b.name.toLowerCase().startsWith(q) ? 0 : 1;
        return as != bs ? as - bs : a.name.compareTo(b.name);
      });
    return hits.take(6).toList();
  }
}

class MentionDirectory {
  static final _db = FirebaseFirestore.instance;
  static Future<List<MentionUser>>? _users;

  static List<MentionUser> _fromDocs(Iterable<DocumentSnapshot> docs) => docs
      .map((d) {
        final data = d.data() as Map<String, dynamic>?;
        final name = (data?['name'] as String?)?.trim() ?? '';
        return MentionUser(d.id, name);
      })
      .where((u) => u.name.isNotEmpty)
      .toList();

  static Future<Set<String>> _blocked(String me) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(me)
          .collection('blocks')
          .get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<List<MentionUser>> _visible(
    List<MentionUser> users,
    String me,
  ) async {
    final blocked = await _blocked(me);
    return users.where((u) => u.uid != me && !blocked.contains(u.uid)).toList();
  }

  /// ผู้ใช้ทั้งหมด (โหลดครั้งเดียวต่อรอบแอป สูงสุด 500 คน เหมือนหน้าค้นหา)
  static Future<List<MentionUser>> all(String me) async {
    final loading = _users ??= _db
        .collection('users')
        .limit(500)
        .get()
        .then((s) => _fromDocs(s.docs))
        .catchError((Object _) {
          _users = null;
          return <MentionUser>[];
        });
    return _visible(await loading, me);
  }

  static Future<List<MentionUser>> byIds(List<String> ids, String me) async {
    final unique = ids.toSet().toList();
    final out = <MentionUser>[];
    for (var i = 0; i < unique.length; i += 30) {
      final chunk = unique.skip(i).take(30).toList();
      final snap = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      out.addAll(_fromDocs(snap.docs));
    }
    return _visible(out, me);
  }
}

/// ส่งแจ้งเตือน "ถูกแท็ก" — ความล้มเหลวของแจ้งเตือนต้องไม่ทำให้การโพสต์/คอมเมนต์ล้มเหลว
class MentionService {
  /// [skip] = uid ที่แท็กไว้ก่อนแล้ว (ตอนแก้ไข จะแจ้งเฉพาะคนที่เพิ่งถูกแท็กเพิ่ม)
  /// [exclude] = uid ที่ได้แจ้งเตือนอื่นของการกระทำเดียวกันไปแล้ว (เช่น เจ้าของโพสต์ที่ได้แจ้งเตือนคอมเมนต์)
  static Future<void> notify({
    required String text,
    required String fromUid,
    required bool inComment,
    required String postId,
    required String source,
    String? sourceId,
    String? sourceName,
    Set<String> skip = const {},
    Set<String> exclude = const {},
  }) async {
    final targets = Mention.uids(text)
      ..remove(fromUid)
      ..removeAll(skip)
      ..removeAll(exclude);
    if (targets.isEmpty) return;
    var snippet = Mention.plain(text).trim();
    if (snippet.length > 80) snippet = snippet.substring(0, 80);
    for (final uid in targets) {
      try {
        await NotificationService().create(
          toUid: uid,
          fromUid: fromUid,
          type: inComment ? NotifType.mentionComment : NotifType.mentionPost,
          postId: postId,
          text: snippet,
          source: source,
          sourceId: sourceId,
          sourceName: sourceName,
        );
      } catch (_) {}
    }
  }
}
