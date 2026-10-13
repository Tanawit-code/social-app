import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import 'profile_screen.dart';
import '../widgets/user_avatar.dart';
import '../utils/image_data.dart';
import 'home_feed_screen.dart' show AuthorName;

/// ค้นหาผู้ใช้ (ตามชื่อ) และโพสต์ (ตามเนื้อหา) + ตัวกรอง "มีรูป" / "ของฉัน"
/// กรองฝั่ง client จากข้อมูลล่าสุด (users 200 คน / posts 100 โพสต์) —
/// เพียงพอสำหรับโปรเจกต์นี้ และไม่ต้องสร้าง index เพิ่ม
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _myUid = AuthService().currentUser?.uid ?? '';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream =
      FirebaseFirestore.instance.collection('users').limit(200).snapshots();
  late final Stream<List<Post>> _postsStream =
      PostService().feedStream(limit: 100);

  Timer? _debounce;
  String _query = '';
  bool _onlyWithImage = false;
  bool _onlyMine = false;

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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'ค้นหาผู้ใช้หรือโพสต์',
              border: InputBorder.none,
            ),
          ),
          bottom: const TabBar(
            tabs: [Tab(text: 'ผู้ใช้'), Tab(text: 'โพสต์')],
          ),
        ),
        body: TabBarView(children: [_users(), _posts()]),
      ),
    );
  }

  Widget _users() {
    if (_query.isEmpty) {
      return const Center(child: Text('พิมพ์ชื่อเพื่อค้นหาผู้ใช้'));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersStream,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('ค้นหาไม่สำเร็จ: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final results = snap.data!.docs.where((d) {
          if (d.id == _myUid) return false;
          final name = ((d.data()['name'] ?? '') as String).toLowerCase();
          return name.contains(_query);
        }).toList();
        if (results.isEmpty) return const Center(child: Text('ไม่พบผู้ใช้'));
        return ListView(
          children: results.map((d) {
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
          }).toList(),
        );
      },
    );
  }

  Widget _posts() {
    final hasFilter = _query.isNotEmpty || _onlyWithImage || _onlyMine;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('มีรูป'),
                selected: _onlyWithImage,
                onSelected: (v) => setState(() => _onlyWithImage = v),
              ),
              FilterChip(
                label: const Text('ของฉัน'),
                selected: _onlyMine,
                onSelected: (v) => setState(() => _onlyMine = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: !hasFilter
              ? const Center(child: Text('พิมพ์คำค้นหา หรือเลือกตัวกรอง'))
              : StreamBuilder<List<Post>>(
                  stream: _postsStream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('ค้นหาไม่สำเร็จ: ${snap.error}'));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final results = snap.data!.where((p) {
                      if (_onlyWithImage && p.mediaUrl == null) return false;
                      if (_onlyMine && p.authorId != _myUid) return false;
                      if (_query.isNotEmpty &&
                          !p.content.toLowerCase().contains(_query)) {
                        return false;
                      }
                      return true;
                    }).toList();
                    if (results.isEmpty) {
                      return const Center(child: Text('ไม่พบโพสต์'));
                    }
                    return ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = results[i];
                        return ListTile(
                          title: AuthorName(uid: p.authorId),
                          subtitle: Text(
                            p.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: p.mediaUrl == null
                              ? null
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
}
