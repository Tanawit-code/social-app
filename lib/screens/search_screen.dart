import '../widgets/privacy_icon.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/community_model.dart';
import '../models/event_model.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../services/event_service.dart';
import '../services/page_service.dart';
import '../services/post_service.dart';
import 'community_detail_screen.dart';
import 'event_detail_screen.dart';
import 'page_detail_screen.dart';
import 'profile_screen.dart';
import '../widgets/user_avatar.dart';
import '../utils/image_data.dart';
import 'home_feed_screen.dart' show AuthorName;

/// ค้นหา 5 หมวด: ผู้ใช้ / โพสต์ / ชุมชน / เพจ / อีเวนต์
/// - พิมพ์คำค้นหาครั้งเดียว ใช้ได้ทุกแท็บ (กรองฝั่ง client จากข้อมูลล่าสุด
///   จึงไม่ต้องสร้าง index เพิ่ม)
/// - ผู้ใช้/โพสต์ มีปุ่ม "โหลดเพิ่ม" เมื่อข้อมูลที่ดึงมาเต็มจำนวน limit
/// - โพสต์: กรองตามประเภทสื่อ (รูป/วิดีโอ) ช่วงเวลา และ "ของฉัน"
/// - ชุมชน/เพจ: กรองตามความเป็นส่วนตัว
/// - อีเวนต์: ซ่อนอีเวนต์ที่ผ่านไปแล้ว/ยกเลิกเป็นค่าเริ่มต้น เปิดดูได้ด้วยตัวกรอง
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _pageStep = 100;

  final _controller = TextEditingController();
  final _myUid = AuthService().currentUser?.uid ?? '';

  int _userLimit = 200;
  int _postLimit = 100;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream =
      _buildUsersStream();
  late Stream<List<Post>> _postsStream = _buildPostsStream();
  late final Stream<List<Community>> _communitiesStream = CommunityService()
      .streamCommunities();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _pagesStream =
      PageService().pages();
  late final Stream<List<SocialEvent>> _eventsStream = EventService().stream();

  Timer? _debounce;
  String _query = '';

  // ตัวกรองโพสต์
  bool _onlyImage = false;
  bool _onlyVideo = false;
  bool _onlyMine = false;
  int _period = 0; // 0 ทั้งหมด, 1 วันนี้, 2 7 วัน, 3 30 วัน

  // ตัวกรองชุมชน/เพจ (null = ทั้งหมด)
  String? _communityPrivacy;
  String? _pagePrivacy;

  // ตัวกรองอีเวนต์
  bool _includePast = false;
  bool _includeCancelled = false;

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildUsersStream() =>
      FirebaseFirestore.instance
          .collection('users')
          .limit(_userLimit)
          .snapshots();

  Stream<List<Post>> _buildPostsStream() =>
      PostService().feedStream(viewerId: _myUid, limit: _postLimit);

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim().toLowerCase());
    });
  }

  bool _has(String? text) =>
      text != null && text.toLowerCase().contains(_query);

  bool _inPeriod(Timestamp? ts) {
    if (_period == 0) return true;
    if (ts == null) return false;
    final now = DateTime.now();
    final cutoff = switch (_period) {
      1 => DateTime(now.year, now.month, now.day),
      2 => now.subtract(const Duration(days: 7)),
      _ => now.subtract(const Duration(days: 30)),
    };
    return ts.toDate().isAfter(cutoff);
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} · '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'ค้นหาผู้ใช้ โพสต์ ชุมชน เพจ หรืออีเวนต์',
              border: InputBorder.none,
            ),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'ผู้ใช้'),
              Tab(text: 'โพสต์'),
              Tab(text: 'ชุมชน'),
              Tab(text: 'เพจ'),
              Tab(text: 'อีเวนต์'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_users(), _posts(), _communities(), _pages(), _events()],
        ),
      ),
    );
  }

  // ---------- ตัวช่วยสร้าง UI ----------

  Widget _chipRow(List<Widget> chips) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, children: chips),
    ),
  );

  Widget _privacyChips(String? value, ValueChanged<String?> onChanged) =>
      _chipRow([
        ChoiceChip(
          label: const Text('ทั้งหมด'),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        ChoiceChip(
          label: const Text('สาธารณะ'),
          selected: value == 'public',
          onSelected: (_) => onChanged('public'),
        ),
        ChoiceChip(
          label: const Text('ส่วนตัว'),
          selected: value == 'private',
          onSelected: (_) => onChanged('private'),
        ),
      ]);

  Widget _loadMore(VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.all(12),
    child: Center(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.expand_more),
        label: const Text('โหลดเพิ่ม'),
      ),
    ),
  );

  Widget _error(Object? e) => Center(child: Text('ค้นหาไม่สำเร็จ: $e'));

  // ---------- ผู้ใช้ ----------

  Widget _users() {
    if (_query.isEmpty) {
      return const Center(child: Text('พิมพ์ชื่อเพื่อค้นหาผู้ใช้'));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersStream,
      builder: (context, snap) {
        if (snap.hasError) return _error(snap.error);
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        final results = docs.where((d) {
          if (d.id == _myUid) return false;
          return _has(d.data()['name'] as String?);
        }).toList();
        final canLoadMore = docs.length >= _userLimit;
        if (results.isEmpty) {
          return Column(
            children: [
              const Expanded(child: Center(child: Text('ไม่พบผู้ใช้'))),
              if (canLoadMore)
                _loadMore(
                  () => setState(() {
                    _userLimit += 200;
                    _usersStream = _buildUsersStream();
                  }),
                ),
            ],
          );
        }
        return ListView(
          children: [
            ...results.map((d) {
              final data = d.data();
              return ListTile(
                leading: UserAvatar(uid: d.id),
                title: Text(data['name'] ?? ''),
                subtitle: (data['bio'] ?? '') == '' ? null : Text(data['bio']),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfileScreen(uid: d.id)),
                ),
              );
            }),
            if (canLoadMore)
              _loadMore(
                () => setState(() {
                  _userLimit += 200;
                  _usersStream = _buildUsersStream();
                }),
              ),
          ],
        );
      },
    );
  }

  // ---------- โพสต์ ----------

  Widget _posts() {
    final hasFilter =
        _query.isNotEmpty ||
        _onlyImage ||
        _onlyVideo ||
        _onlyMine ||
        _period != 0;
    const periodLabels = ['ทั้งหมด', 'วันนี้', '7 วัน', '30 วัน'];
    return Column(
      children: [
        _chipRow([
          FilterChip(
            label: const Text('รูปภาพ'),
            selected: _onlyImage,
            onSelected: (v) => setState(() => _onlyImage = v),
          ),
          FilterChip(
            label: const Text('วิดีโอ'),
            selected: _onlyVideo,
            onSelected: (v) => setState(() => _onlyVideo = v),
          ),
          FilterChip(
            label: const Text('ของฉัน'),
            selected: _onlyMine,
            onSelected: (v) => setState(() => _onlyMine = v),
          ),
        ]),
        _chipRow([
          for (var i = 0; i < periodLabels.length; i++)
            ChoiceChip(
              label: Text(periodLabels[i]),
              selected: _period == i,
              onSelected: (_) => setState(() => _period = i),
            ),
        ]),
        Expanded(
          child: !hasFilter
              ? const Center(child: Text('พิมพ์คำค้นหา หรือเลือกตัวกรอง'))
              : StreamBuilder<List<Post>>(
                  stream: _postsStream,
                  builder: (context, snap) {
                    if (snap.hasError) return _error(snap.error);
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final all = snap.data!;
                    final results = all.where((p) {
                      if (_onlyImage &&
                          !(p.mediaUrl != null && p.mediaType != 'video')) {
                        return false;
                      }
                      if (_onlyVideo &&
                          !(p.mediaUrl != null && p.mediaType == 'video')) {
                        return false;
                      }
                      if (_onlyMine && p.authorId != _myUid) return false;
                      if (!_inPeriod(p.createdAt)) return false;
                      if (_query.isNotEmpty && !_has(p.content)) return false;
                      return true;
                    }).toList();
                    final canLoadMore = all.length >= _postLimit;
                    void loadMore() => setState(() {
                      _postLimit += _pageStep;
                      _postsStream = _buildPostsStream();
                    });
                    if (results.isEmpty) {
                      return Column(
                        children: [
                          const Expanded(
                            child: Center(child: Text('ไม่พบโพสต์')),
                          ),
                          if (canLoadMore) _loadMore(loadMore),
                        ],
                      );
                    }
                    return ListView.separated(
                      itemCount: results.length + (canLoadMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        if (i == results.length) return _loadMore(loadMore);
                        final p = results[i];
                        return ListTile(
                          title: Row(
                            children: [
                              Flexible(child: AuthorName(uid: p.authorId)),
                              const SizedBox(width: 6),
                              PostPrivacyIcon(
                                audience: p.audience,
                                pageId: p.pageId,
                              ),
                            ],
                          ),
                          subtitle: Text(
                            p.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: p.mediaUrl == null
                              ? null
                              : p.mediaType == 'video'
                              ? const Icon(Icons.videocam_outlined)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: AppImage(
                                    src: p.mediaUrl!,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------- ชุมชน ----------

  Widget _communities() {
    return StreamBuilder<List<Community>>(
      stream: _communitiesStream,
      builder: (context, snap) {
        if (snap.hasError) return _error(snap.error);
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data!.where((c) {
          if (_communityPrivacy != null && c.privacy != _communityPrivacy) {
            return false;
          }
          return _query.isEmpty || _has(c.name) || _has(c.description);
        }).toList();
        return Column(
          children: [
            _privacyChips(
              _communityPrivacy,
              (v) => setState(() => _communityPrivacy = v),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('ไม่พบชุมชน'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final c = items[i];
                        final isPrivate = c.privacy == 'private';
                        return ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              isPrivate ? Icons.lock_outline : Icons.groups,
                            ),
                          ),
                          title: Text(c.name),
                          subtitle: Text(
                            c.description.isEmpty
                                ? (isPrivate ? 'ส่วนตัว' : 'สาธารณะ')
                                : c.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CommunityDetailScreen(community: c),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ---------- เพจ ----------

  Widget _pages() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _pagesStream,
      builder: (context, snap) {
        if (snap.hasError) return _error(snap.error);
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs.where((d) {
          final data = d.data();
          final privacy = data['privacy'] as String? ?? 'public';
          if (_pagePrivacy != null && privacy != _pagePrivacy) return false;
          return _query.isEmpty ||
              _has(data['name'] as String?) ||
              _has(data['description'] as String?);
        }).toList();
        return Column(
          children: [
            _privacyChips(
              _pagePrivacy,
              (v) => setState(() => _pagePrivacy = v),
            ),
            Expanded(
              child: docs.isEmpty
                  ? const Center(child: Text('ไม่พบเพจ'))
                  : ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final doc = docs[i];
                        final data = doc.data();
                        final photo = data['photoUrl'] as String? ?? '';
                        final isPrivate = data['privacy'] == 'private';
                        final members = List<String>.from(
                          data['memberIds'] ?? const [],
                        );
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: imageProviderFor(photo),
                            child: photo.isNotEmpty
                                ? null
                                : Icon(
                                    isPrivate
                                        ? Icons.lock_outline
                                        : Icons.flag_outlined,
                                  ),
                          ),
                          title: Text(data['name'] ?? 'เพจ'),
                          subtitle: Text(
                            '${isPrivate ? 'ส่วนตัว' : 'สาธารณะ'} · สมาชิก ${members.length} คน',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PageDetailScreen(pageId: doc.id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ---------- อีเวนต์ ----------

  Widget _events() {
    return StreamBuilder<List<SocialEvent>>(
      stream: _eventsStream,
      builder: (context, snap) {
        if (snap.hasError) return _error(snap.error);
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final now = DateTime.now();
        final items = snap.data!.where((e) {
          if (!_includeCancelled && e.isCancelled) return false;
          if (!_includePast && e.startAt.toDate().isBefore(now)) return false;
          return _query.isEmpty ||
              _has(e.name) ||
              _has(e.location) ||
              _has(e.description);
        }).toList();
        return Column(
          children: [
            _chipRow([
              FilterChip(
                label: const Text('รวมที่ผ่านมาแล้ว'),
                selected: _includePast,
                onSelected: (v) => setState(() => _includePast = v),
              ),
              FilterChip(
                label: const Text('รวมที่ยกเลิก'),
                selected: _includeCancelled,
                onSelected: (v) => setState(() => _includeCancelled = v),
              ),
            ]),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('ไม่พบอีเวนต์'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = items[i];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.event_available_outlined),
                          ),
                          title: Text(
                            e.isCancelled ? '${e.name} (ยกเลิก)' : e.name,
                          ),
                          subtitle: Text(
                            '${_fmtDate(e.startAt.toDate())}${e.location.isEmpty ? '' : ' · ${e.location}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventDetailScreen(event: e),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
