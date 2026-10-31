import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/storage_service.dart';
import '../services/safety_service.dart';
import '../services/post_service.dart';
import '../services/friend_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/post_media.dart';
import '../utils/image_data.dart';
import 'chat_screen.dart';
import 'privacy_settings_screen.dart';
import 'account_settings_screen.dart';
import 'home_feed_screen.dart'
    show AuthorName, EditPostDialog, formatRelativeTime, invalidateAuthorName;

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
  final _safetyService = SafetyService();
  final _postService = PostService();
  final _friendService = FriendService();

  late final String _myUid = _authService.currentUser?.uid ?? '';
  late final String _targetUid = widget.uid ?? _myUid;
  bool get _isMe => _targetUid == _myUid;
  late Future<FriendRequestState> _friendStatus = _friendService.state(
    _myUid,
    _targetUid,
  );

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
  bool _followRequestPending = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    if (!_isMe) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('followRequests')
          .doc(_myUid)
          .get()
          .then((request) {
            if (mounted && request.exists)
              setState(() => _followRequestPending = true);
          });
    }
  }

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
        final sentRequest = await _followService.follow(
          me: _myUid,
          target: _targetUid,
        );
        if (mounted) {
          setState(() => _followRequestPending = sentRequest);
          _toast(sentRequest ? 'ส่งคำขอติดตามแล้ว' : 'ติดตามแล้ว');
        }
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

  Future<void> _editProfile(
    String name,
    String bio,
    String photoUrl, {
    bool isPrivate = false,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProfileDialog(
        uid: _myUid,
        initialName: name,
        initialBio: bio,
        initialPhotoUrl: photoUrl,
        initialIsPrivate: isPrivate,
        authService: _authService,
      ),
    );
    if (saved == true) {
      invalidateAuthorName(
        _myUid,
      ); // ให้ชื่อใหม่แสดงในฟีด/คอมเมนต์ที่โหลดครั้งถัดไป
      _toast('บันทึกโปรไฟล์แล้ว');
    }
  }

  Future<void> _editPost(Post post) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EditPostDialog(post: post, postService: _postService),
    );
    if (saved == true) _toast('บันทึกการแก้ไขโพสต์แล้ว');
  }

  Future<void> _performFriendAction(FriendRequestState status) async {
    setState(() => _busy = true);
    try {
      switch (status) {
        case FriendRequestState.none:
          await _friendService.send(from: _myUid, to: _targetUid);
          _toast('ส่งคำขอเป็นเพื่อนแล้ว');
          break;
        case FriendRequestState.sent:
          await _friendService.cancel(sender: _myUid, receiver: _targetUid);
          _toast('ยกเลิกคำขอแล้ว');
          break;
        case FriendRequestState.incoming:
          await _friendService.accept(receiver: _myUid, sender: _targetUid);
          _toast('เพิ่มเป็นเพื่อนแล้ว');
          break;
        case FriendRequestState.friends:
          await _friendService.unfriend(me: _myUid, other: _targetUid);
          _toast('เลิกเป็นเพื่อนแล้ว');
          break;
      }
      if (mounted)
        setState(
          () => _friendStatus = _friendService.state(_myUid, _targetUid),
        );
    } catch (error) {
      _toast('ทำรายการไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _friendButton() => FutureBuilder<FriendRequestState>(
    future: _friendStatus,
    builder: (context, snapshot) {
      final status = snapshot.data ?? FriendRequestState.none;
      final label = switch (status) {
        FriendRequestState.friends => 'เพื่อนแล้ว',
        FriendRequestState.sent => 'ยกเลิกคำขอเป็นเพื่อน',
        FriendRequestState.incoming => 'ยอมรับคำขอเป็นเพื่อน',
        FriendRequestState.none => 'เพิ่มเพื่อน',
      };
      final icon = switch (status) {
        FriendRequestState.friends => Icons.people,
        FriendRequestState.sent => Icons.person_remove_alt_1,
        FriendRequestState.incoming => Icons.person_add_alt_1,
        FriendRequestState.none => Icons.person_add_alt_1,
      };
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy || !snapshot.hasData
              ? null
              : () => _performFriendAction(status),
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );
    },
  );

  void _manageFeedControls() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _FeedControlsSheet(uid: _myUid, postService: _postService),
    );
  }

  Future<void> _reportProfile() async {
    final reasons = [
      'สแปม',
      'เนื้อหาไม่เหมาะสม',
      'คุกคามหรือแอบอ้าง',
      'อื่น ๆ',
    ];
    String reason = reasons.first;
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('รายงานโปรไฟล์'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => DropdownButtonFormField<String>(
            value: reason,
            items: reasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) {
              if (v != null) setDialogState(() => reason = v);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ส่งรายงาน'),
          ),
        ],
      ),
    );
    if (sent != true) return;
    try {
      await _safetyService.report(
        targetType: 'profile',
        targetId: _targetUid,
        reason: reason,
      );
      _toast('ส่งรายงานแล้ว ขอบคุณที่แจ้งให้ทราบ');
    } catch (e) {
      _toast('ส่งรายงานไม่สำเร็จ: $e');
    }
  }

  Future<void> _blockProfile(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('บล็อก ${name.isEmpty ? 'ผู้ใช้นี้' : name}?'),
        content: const Text(
          'โปรไฟล์และโพสต์จะถูกซ่อนจากกัน และจะป้องกันการส่งข้อความระหว่างบัญชีนี้กับคุณ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บล็อก'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _safetyService.block(_targetUid);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast('บล็อกไม่สำเร็จ: $e');
    }
  }

  void _showBlockedUsers() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'บัญชีที่บล็อก',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(_myUid)
                      .collection('blocks')
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError)
                      return const Center(
                        child: Text('โหลดรายการบล็อกไม่สำเร็จ'),
                      );
                    if (!snap.hasData)
                      return const Center(child: CircularProgressIndicator());
                    if (snap.data!.docs.isEmpty)
                      return const Center(child: Text('ยังไม่มีบัญชีที่บล็อก'));
                    return ListView(
                      children: snap.data!.docs
                          .map(
                            (doc) => ListTile(
                              leading: const Icon(Icons.block),
                              title: Text(
                                'บัญชี ${doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length)}',
                              ),
                              trailing: TextButton(
                                onPressed: () async {
                                  try {
                                    await _safetyService.unblock(doc.id);
                                  } catch (e) {
                                    if (mounted)
                                      _toast('ปลดบล็อกไม่สำเร็จ: $e');
                                  }
                                },
                                child: const Text('ปลดบล็อก'),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ยืนยันตัวตนก่อนลบบัญชี'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, passwordController.text),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    passwordController.dispose();
    if (password == null || password.isEmpty) return;

    setState(() => _deleting = true);
    final error = await _authService.deleteAccount(_myUid, password: password);

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
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
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

  Widget _actions(
    String name,
    String bio,
    String photoUrl,
    bool isFollowing,
    bool isPrivate,
  ) {
    if (_isMe) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: _btnStyle(bg: _fbBlue, fg: Colors.white),
            onPressed: () =>
                _editProfile(name, bio, photoUrl, isPrivate: isPrivate),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('แก้ไขโปรไฟล์'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('ความเป็นส่วนตัวและคำขอติดตาม'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
            ),
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('บัญชี อีเมล รหัสผ่าน และการแจ้งเตือน'),
          ),
          TextButton.icon(
            onPressed: _manageFeedControls,
            icon: const Icon(Icons.tune),
            label: const Text('จัดการฟีดและโพสต์ที่ซ่อน'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                      onPressed: _busy
                          ? null
                          : () async {
                              if (_followRequestPending) {
                                await _followService.cancelRequest(
                                  requester: _myUid,
                                  owner: _targetUid,
                                );
                                if (mounted)
                                  setState(() => _followRequestPending = false);
                              } else {
                                await _toggleFollow(false);
                              }
                            },
                      icon: Icon(
                        _followRequestPending
                            ? Icons.hourglass_top
                            : Icons.person_add_alt_1,
                        size: 18,
                      ),
                      label: Text(
                        _followRequestPending
                            ? '\u0e2a\u0e48\u0e07\u0e04\u0e33\u0e02\u0e2d\u0e41\u0e25\u0e49\u0e27'
                            : '\u0e15\u0e34\u0e14\u0e15\u0e32\u0e21',
                      ),
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
            const SizedBox(width: 6),
            SizedBox(
              width: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 44),
                  padding: EdgeInsets.zero,
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final action = await showModalBottomSheet<String>(
                          context: context,
                          builder: (ctx) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.flag_outlined),
                                  title: const Text('รายงานโปรไฟล์'),
                                  onTap: () => Navigator.pop(ctx, 'report'),
                                ),
                                ListTile(
                                  leading: const Icon(
                                    Icons.block,
                                    color: Colors.red,
                                  ),
                                  title: const Text('บล็อกผู้ใช้นี้'),
                                  onTap: () => Navigator.pop(ctx, 'block'),
                                ),
                              ],
                            ),
                          ),
                        );
                        if (action == 'report') await _reportProfile();
                        if (action == 'block') await _blockProfile(name);
                      },
                child: const Icon(Icons.more_horiz),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _friendButton(),
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
          TextSpan(
            children: [
              TextSpan(
                text: '$n',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: ' $label  ›'),
            ],
          ),
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$title (${userIds.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'ปิด',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (userIds.isEmpty)
                Expanded(child: Center(child: Text('ยังไม่มี$title')))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: userIds.length,
                    itemBuilder: (context, index) {
                      final uid = userIds[index];
                      return ListTile(
                        leading: UserAvatar(uid: uid),
                        title: AuthorName(uid: uid),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          Navigator.push(
                            this.context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(uid: uid),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(
    String name,
    String bio,
    String photoUrl,
    String coverUrl,
    bool isPrivate,
  ) {
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
                        onTap: () => _editProfile(
                          name,
                          bio,
                          photoUrl,
                          isPrivate: isPrivate,
                        ),
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
              child: Text(
                'ยังไม่มีโพสต์',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          );
        }
        return Column(
          children: posts
              .map(
                (p) => _PostTile(
                  post: p,
                  canEdit: _isMe,
                  onEdit: () => _editPost(p),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _visibleProfilePosts({
    required bool isPrivate,
    required bool isFollowing,
  }) {
    if (_isMe || !isPrivate || isFollowing) return _postsSection();
    return FutureBuilder<FriendRequestState>(
      future: _friendStatus,
      builder: (context, snapshot) {
        if (snapshot.data == FriendRequestState.friends) return _postsSection();
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'บัญชีนี้เป็นส่วนตัว โพสต์จะแสดงเมื่อเป็นเพื่อนกันแล้ว',
            ),
          ),
        );
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
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ดูโปรไฟล์นี้ไม่ได้ บัญชีอาจเป็นส่วนตัวหรือผู้ใช้นี้บล็อกคุณ',
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return _page(
            'โปรไฟล์',
            const Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data!.data();
        if (data == null) {
          return _page('โปรไฟล์', const Center(child: Text('ไม่พบผู้ใช้นี้')));
        }
        final name = (data['name'] ?? '') as String;
        final bio = (data['bio'] ?? '') as String;
        final photoUrl = (data['photoUrl'] ?? '') as String;
        final coverUrl = (data['coverUrl'] ?? '') as String;
        final isPrivate = data['isPrivate'] == true;
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
                    _cover(name, bio, photoUrl, coverUrl, isPrivate),
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
                          _actions(name, bio, photoUrl, isFollowing, isPrivate),
                          const SizedBox(height: 12),
                          _infoRow(
                            Icons.people_alt_outlined,
                            _countText(
                              followers.length,
                              'ผู้ติดตาม',
                              () => _showFollowList('ผู้ติดตาม', followers),
                            ),
                          ),
                          _infoRow(
                            Icons.person_add_alt_outlined,
                            _countText(
                              following.length,
                              'กำลังติดตาม',
                              () => _showFollowList('กำลังติดตาม', following),
                            ),
                          ),
                          if (_isMe)
                            StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>
                            >(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(_myUid)
                                  .collection('private')
                                  .doc('account')
                                  .snapshots(),
                              builder: (context, accountSnap) {
                                final email =
                                    accountSnap.data?.data()?['email']
                                        as String? ??
                                    '';
                                return email.isEmpty
                                    ? const SizedBox.shrink()
                                    : _infoRow(Icons.mail_outline, Text(email));
                              },
                            ),
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
                    _visibleProfilePosts(
                      isPrivate: isPrivate,
                      isFollowing: isFollowing,
                    ),
                    if (_isMe) ...[
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _showBlockedUsers,
                        icon: const Icon(Icons.block_outlined),
                        label: const Text('จัดการบัญชีที่บล็อก'),
                      ),
                      const SizedBox(height: 12),
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
  final bool canEdit;
  final VoidCallback onEdit;
  const _PostTile({
    required this.post,
    required this.canEdit,
    required this.onEdit,
  });

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
                if (canEdit)
                  IconButton(
                    tooltip: 'แก้ไขโพสต์',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
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

class _FeedControlsSheet extends StatelessWidget {
  final String uid;
  final PostService postService;
  const _FeedControlsSheet({required this.uid, required this.postService});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.of(context).size.height * .7,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'จัดการฟีด',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'โพสต์ที่ซ่อน',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('hiddenPosts')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                if (snapshot.data!.docs.isEmpty)
                  return const ListTile(title: Text('ยังไม่มีโพสต์ที่ซ่อน'));
                return Column(
                  children: snapshot.data!.docs
                      .map(
                        (doc) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.visibility_off_outlined),
                          title: Text(
                            'โพสต์ ${doc.id.substring(0, doc.id.length > 8 ? 8 : doc.id.length)}…',
                          ),
                          trailing: TextButton(
                            onPressed: () =>
                                postService.unhidePost(uid, doc.id),
                            child: const Text('เลิกซ่อน'),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const Divider(),
            const Text(
              'บัญชีที่ซ่อน',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('mutedAuthors')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                if (snapshot.data!.docs.isEmpty)
                  return const ListTile(title: Text('ยังไม่มีบัญชีที่ซ่อน'));
                return Column(
                  children: snapshot.data!.docs
                      .map(
                        (doc) => ListTile(
                          dense: true,
                          leading: UserAvatar(uid: doc.id, radius: 18),
                          title: AuthorName(uid: doc.id),
                          trailing: TextButton(
                            onPressed: () =>
                                postService.unmuteAuthor(uid, doc.id),
                            child: const Text('เลิกซ่อน'),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _EditProfileDialog extends StatefulWidget {
  final String uid;
  final String initialName;
  final String initialBio;
  final String initialPhotoUrl;
  final bool initialIsPrivate;
  final AuthService authService;

  const _EditProfileDialog({
    required this.uid,
    required this.initialName,
    required this.initialBio,
    required this.initialPhotoUrl,
    required this.initialIsPrivate,
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
  late bool _isPrivate = widget.initialIsPrivate;
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
      isPrivate: _isPrivate,
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isPrivate,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _isPrivate = value),
              title: const Text('บัญชีส่วนตัว'),
              subtitle: const Text(
                'เฉพาะผู้ติดตามที่อนุมัติแล้วจึงจะเห็นโพสต์',
              ),
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
