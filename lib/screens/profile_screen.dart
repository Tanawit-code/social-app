import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/storage_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/post_media.dart';
import '../utils/image_data.dart';
import 'chat_screen.dart';
import 'home_feed_screen.dart'
    show AuthorName, formatRelativeTime, invalidateAuthorName;

/// โปรไฟล์ — ไม่ส่ง uid = โปรไฟล์ของตัวเอง (แก้ไขได้)
/// ส่ง uid ของคนอื่น = ดูโปรไฟล์ + ติดตาม/เลิกติดตาม + ส่งข้อความ
class ProfileScreen extends StatefulWidget {
  final String? uid;
  const ProfileScreen({this.uid, super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _followService = FollowService();

  late final String _myUid = _authService.currentUser?.uid ?? '';
  late final String _targetUid = widget.uid ?? _myUid;
  bool get _isMe => _targetUid == _myUid;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream =
      FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .snapshots();

  // ไม่ใช้ orderBy ร่วมกับ where เพื่อไม่ต้องสร้าง composite index — เรียงฝั่ง client แทน
  late final Stream<List<Post>> _postsStream = FirebaseFirestore.instance
      .collection('posts')
      .where('authorId', isEqualTo: _targetUid)
      .snapshots()
      .map((snap) {
        final now = DateTime.now().millisecondsSinceEpoch;
        int t(Post p) => p.createdAt?.millisecondsSinceEpoch ?? now;
        final list = snap.docs.map((d) => Post.fromDoc(d)).toList();
        list.sort((a, b) => t(b).compareTo(t(a)));
        return list;
      });

  bool _busy = false;
  bool _deleting = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleFollow(bool isFollowing) async {
    setState(() => _busy = true);
    try {
      if (isFollowing) {
        await _followService.unfollow(me: _myUid, target: _targetUid);
      } else {
        await _followService.follow(me: _myUid, target: _targetUid);
      }
    } catch (e) {
      _toast('ทำรายการไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// เมนูเปลี่ยน/ลบรูปปก (เฉพาะโปรไฟล์ตัวเอง)
  Future<void> _coverMenu(String coverUrl) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปปกจากเครื่อง'),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            if (coverUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('ลบรูปปก (กลับเป็นพื้นสีเดิม)'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == 'pick') await _pickCover();
    if (action == 'remove') await _saveCover('');
  }

  Future<void> _pickCover() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 1024,
        maxHeight: 400,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final url = await StorageService().uploadCoverImageBytes(
        bytes: bytes,
        uid: _myUid,
      );
      await _saveCover(url);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _saveCover(String url) async {
    setState(() => _busy = true);
    final err = await _authService.updateProfile(uid: _myUid, coverUrl: url);
    if (mounted) setState(() => _busy = false);
    _toast(err ?? (url.isEmpty ? 'ลบรูปปกแล้ว' : 'เปลี่ยนรูปปกแล้ว'));
  }

  Future<void> _editProfile(String name, String bio, String photoUrl) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProfileDialog(
        uid: _myUid,
        initialName: name,
        initialBio: bio,
        initialPhotoUrl: photoUrl,
        authService: _authService,
      ),
    );
    if (saved == true) {
      invalidateAuthorName(_myUid); // ให้ชื่อใหม่แสดงในฟีด/คอมเมนต์ที่โหลดครั้งถัดไป
      _toast('บันทึกโปรไฟล์แล้ว');
    }
  }

  Future<void> _confirmDeleteAccount() async {
    if (_myUid.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบบัญชีถาวร?'),
        content: const Text(
          'การลบบัญชีจะลบโพสต์ทั้งหมดของคุณ รวมถึงคอมเมนต์และไลก์ในโพสต์เหล่านั้นด้วย '
          'และไม่สามารถกู้คืนได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบบัญชี'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    final error = await _authService.deleteAccount(_myUid);

    if (!mounted) return;

    if (error != null) {
      setState(() => _deleting = false);
      _toast(error);
      return;
    }

    // สำเร็จ: เคลียร์ stack ทั้งหมดกลับไปหน้า login
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  static const _fbBlue = Color(0xFF1877F2);
  static const _pageBg = Color(0xFFF0F2F5);
  static const _btnGrey = Color(0xFFE4E6EB);
  static const _months = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  Future<void> _confirmUnfollow(String name) async {
    final who = name.isEmpty ? 'ผู้ใช้นี้' : name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('เลิกติดตาม $who?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เลิกติดตาม'),
          ),
        ],
      ),
    );
    if (ok == true) await _toggleFollow(true);
  }

  ButtonStyle _btnStyle({required Color bg, required Color fg}) {
    return FilledButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      minimumSize: const Size.fromHeight(44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _actions(String name, String bio, String photoUrl, bool isFollowing) {
    if (_isMe) {
      return FilledButton.icon(
        style: _btnStyle(bg: _fbBlue, fg: Colors.white),
        onPressed: () => _editProfile(name, bio, photoUrl),
        icon: const Icon(Icons.edit, size: 18),
        label: const Text('แก้ไขโปรไฟล์'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: isFollowing
              ? FilledButton.icon(
                  style: _btnStyle(bg: _btnGrey, fg: Colors.black87),
                  onPressed: _busy ? null : () => _confirmUnfollow(name),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('กำลังติดตาม'),
                )
              : FilledButton.icon(
                  style: _btnStyle(bg: _fbBlue, fg: Colors.white),
                  onPressed: _busy ? null : () => _toggleFollow(false),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('ติดตาม'),
                ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: FilledButton(
            style: _btnStyle(bg: _btnGrey, fg: Colors.black87).copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(peerUid: _targetUid),
              ),
            ),
            child: const Icon(Icons.chat_bubble, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _countText(int n, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$n', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: ' $label  ›'),
          ]),
        ),
      ),
    );
  }

  void _showFollowList(String title, List<String> userIds) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
              child: Row(children: [
                Expanded(child: Text('$title (${userIds.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                IconButton(tooltip: 'ปิด', onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
              ]),
            ),
            const Divider(height: 1),
            if (userIds.isEmpty)
              Expanded(child: Center(child: Text('ยังไม่มี$title')))
            else
              Expanded(child: ListView.builder(
                itemCount: userIds.length,
                itemBuilder: (context, index) {
                  final uid = userIds[index];
                  return ListTile(
                    leading: UserAvatar(uid: uid),
                    title: AuthorName(uid: uid),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Navigator.push(this.context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)));
                    },
                  );
                },
              )),
          ]),
        ),
      ),
    );
  }

  Widget _cover(String name, String bio, String photoUrl, String coverUrl) {
    // ปกไล่สี + รูปโปรไฟล์วงกลมใหญ่ซ้อนขอบล่างของปก (สูงรวม 150 + ครึ่งรูป)
    return SizedBox(
      height: 206,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6750A4), Color(0xFF1877F2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              // มีรูปปกก็แสดงทับพื้นไล่สี (ไม่มี/โหลดไม่ได้ = เห็นพื้นไล่สีเหมือนเดิม)
              child: coverUrl.isEmpty
                  ? null
                  : Image(
                      image: imageProviderFor(coverUrl) ?? const AssetImage(''),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 150,
                      gaplessPlayback: true,
                      semanticLabel: 'รูปปกโปรไฟล์',
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
            ),
          ),
          if (_isMe)
            Positioned(
              top: 8,
              right: 8,
              child: FilledButton.tonalIcon(
                onPressed: _busy ? null : () => _coverMenu(coverUrl),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('เปลี่ยนปก'),
              ),
            ),
          Positioned(
            top: 94,
            left: 0,
            right: 0,
            child: Center(
              child: Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: PhotoAvatar(url: photoUrl, radius: 52),
                  ),
                  if (_isMe)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: GestureDetector(
                        onTap: () => _editProfile(name, bio, photoUrl),
                        child: const CircleAvatar(
                          radius: 16,
                          backgroundColor: _btnGrey,
                          child: Icon(
                            Icons.camera_alt,
                            size: 18,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _postsSection() {
    return StreamBuilder<List<Post>>(
      stream: _postsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('โหลดโพสต์ไม่สำเร็จ: ${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final posts = snap.data!;
        if (posts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text('ยังไม่มีโพสต์', style: TextStyle(color: Colors.black54)),
            ),
          );
        }
        return Column(children: posts.map((p) => _PostTile(post: p)).toList());
      },
    );
  }

  Widget _page(String title, Widget body) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_deleting) {
      return _page('', const Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _page(
            'โปรไฟล์',
            Center(child: Text('โหลดโปรไฟล์ไม่สำเร็จ: ${snap.error}')),
          );
        }
        if (!snap.hasData) {
          return _page('โปรไฟล์', const Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!.data();
        if (data == null) {
          return _page('โปรไฟล์', const Center(child: Text('ไม่พบผู้ใช้นี้')));
        }
        final name = (data['name'] ?? '') as String;
        final bio = (data['bio'] ?? '') as String;
        final email = (data['email'] ?? '') as String;
        final photoUrl = (data['photoUrl'] ?? '') as String;
        final coverUrl = (data['coverUrl'] ?? '') as String;
        final followers = List<String>.from(data['followers'] ?? []);
        final following = List<String>.from(data['following'] ?? []);
        final isFollowing = followers.contains(_myUid);
        final joined = (data['createdAt'] as Timestamp?)?.toDate();

        return _page(
          name.isEmpty ? 'โปรไฟล์' : name,
          ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                color: Colors.white,
                child: Column(
                  children: [
                    _cover(name, bio, photoUrl, coverUrl),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            name.isEmpty ? 'ผู้ใช้ไม่ทราบชื่อ' : name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (bio.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              bio,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _actions(name, bio, photoUrl, isFollowing),
                          const SizedBox(height: 12),
                          _infoRow(
                            Icons.people_alt_outlined,
                            _countText(followers.length, 'ผู้ติดตาม', () => _showFollowList('ผู้ติดตาม', followers)),
                          ),
                          _infoRow(
                            Icons.person_add_alt_outlined,
                            _countText(following.length, 'กำลังติดตาม', () => _showFollowList('กำลังติดตาม', following)),
                          ),
                          if (_isMe && email.isNotEmpty)
                            _infoRow(Icons.mail_outline, Text(email)),
                          if (joined != null)
                            _infoRow(
                              Icons.calendar_month_outlined,
                              Text(
                                'เข้าร่วมเมื่อ ${joined.day} ${_months[joined.month - 1]} ${joined.year + 543}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: _pageBg,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 6, 4, 10),
                      child: Text(
                        'โพสต์',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _postsSection(),
                    if (_isMe) ...[
                      const SizedBox(height: 24),
                      Text(
                        'โซนอันตราย',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: _confirmDeleteAccount,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('ลบบัญชีถาวร'),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PostTile extends StatelessWidget {
  final Post post;
  const _PostTile({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(uid: post.authorId, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AuthorName(uid: post.authorId),
                      Text(
                        formatRelativeTime(post.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (post.content.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(post.content, style: const TextStyle(fontSize: 15)),
            ],
            if (post.mediaUrl != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PostMedia(
                  url: post.mediaUrl!,
                  type: post.mediaType,
                  errorHeight: 120,
                ),
              ),
            ],
            if (post.likeCount > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.thumb_up, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    '${post.likeCount}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  final String uid;
  final String initialName;
  final String initialBio;
  final String initialPhotoUrl;
  final AuthService authService;

  const _EditProfileDialog({
    required this.uid,
    required this.initialName,
    required this.initialBio,
    required this.initialPhotoUrl,
    required this.authService,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  static const _maxPhotoBytes = 5 * 1024 * 1024;

  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.initialBio,
  );
  final _picker = ImagePicker();
  final _storage = StorageService();

  Uint8List? _newPhoto; // รูปใหม่ที่เลือกไว้ (ยังไม่อัปโหลดจนกว่าจะกดบันทึก)
  bool _removePhoto = false; // true = ลบรูปเดิมทิ้ง
  bool _saving = false;
  String? _error;

  bool get _hasCurrentPhoto =>
      !_removePhoto && widget.initialPhotoUrl.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 256,
        maxHeight: 256,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxPhotoBytes) {
        setState(() => _error = 'รูปใหญ่เกิน 5 MB');
        return;
      }
      setState(() {
        _newPhoto = bytes;
        _removePhoto = false;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'เลือกรูปไม่สำเร็จ ลองใหม่อีกครั้ง');
    }
  }

  void _clearPhoto() {
    setState(() {
      _newPhoto = null;
      _removePhoto = widget.initialPhotoUrl.isNotEmpty;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'กรุณากรอกชื่อ');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    String? photoUrl; // null = ไม่เปลี่ยนรูป, '' = ลบรูป
    try {
      if (_newPhoto != null) {
        photoUrl = await _storage.uploadProfileImageBytes(
          bytes: _newPhoto!,
          uid: widget.uid,
        );
      } else if (_removePhoto) {
        photoUrl = '';
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    final err = await widget.authService.updateProfile(
      uid: widget.uid,
      name: name,
      bio: _bio.text.trim(),
      photoUrl: photoUrl,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }

    // เปลี่ยน/ลบรูปสำเร็จแล้ว จึงลบไฟล์รูปเก่าทิ้ง (ไม่รอผล)
    if (photoUrl != null && widget.initialPhotoUrl.isNotEmpty) {
      _storage.deleteByUrl(widget.initialPhotoUrl);
    }
    Navigator.pop(context, true);
  }

  Widget _preview() {
    ImageProvider? img;
    if (_newPhoto != null) {
      img = MemoryImage(_newPhoto!);
    } else if (_hasCurrentPhoto) {
      img = imageProviderFor(widget.initialPhotoUrl);
    }
    return CircleAvatar(
      radius: 44,
      backgroundImage: img,
      child: img == null ? const Icon(Icons.person, size: 40) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('แก้ไขโปรไฟล์'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _preview(),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('เปลี่ยนรูป'),
                ),
                if (_newPhoto != null || _hasCurrentPhoto)
                  TextButton.icon(
                    onPressed: _saving ? null : _clearPhoto,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('ลบรูป'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'ชื่อ'),
            ),
            TextField(
              controller: _bio,
              maxLength: 150,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'ประวัติย่อ'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('บันทึก'),
        ),
      ],
    );
  }
}
