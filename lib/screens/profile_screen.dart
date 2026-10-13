import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../services/storage_service.dart';
import '../widgets/user_avatar.dart';
import '../utils/image_data.dart';
import 'chat_screen.dart';
import 'home_feed_screen.dart' show formatRelativeTime, invalidateAuthorName;

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

  Widget _stat(String label, int count) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
      ],
    );
  }

  Widget _actions(String name, String bio, String photoUrl, bool isFollowing) {
    if (_isMe) {
      return OutlinedButton.icon(
        onPressed: () => _editProfile(name, bio, photoUrl),
        icon: const Icon(Icons.edit),
        label: const Text('แก้ไขโปรไฟล์'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: isFollowing
              ? OutlinedButton.icon(
                  onPressed: _busy ? null : () => _toggleFollow(true),
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('เลิกติดตาม'),
                )
              : FilledButton.icon(
                  onPressed: _busy ? null : () => _toggleFollow(false),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('ติดตาม'),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(peerUid: _targetUid),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('ข้อความ'),
          ),
        ),
      ],
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
            padding: EdgeInsets.all(20),
            child: Center(child: Text('ยังไม่มีโพสต์')),
          );
        }
        return Column(children: posts.map((p) => _PostTile(post: p)).toList());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isMe ? 'โปรไฟล์ของฉัน' : 'โปรไฟล์')),
      body: _deleting
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _userStream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('โหลดโปรไฟล์ไม่สำเร็จ: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snap.data!.data();
                if (data == null) {
                  return const Center(child: Text('ไม่พบผู้ใช้นี้'));
                }
                final name = (data['name'] ?? '') as String;
                final bio = (data['bio'] ?? '') as String;
                final email = (data['email'] ?? '') as String;
                final photoUrl = (data['photoUrl'] ?? '') as String;
                final followers = List<String>.from(data['followers'] ?? []);
                final following = List<String>.from(data['following'] ?? []);
                final isFollowing = followers.contains(_myUid);

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(child: PhotoAvatar(url: photoUrl, radius: 44)),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        name.isEmpty ? 'ผู้ใช้ไม่ทราบชื่อ' : name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_isMe && email.isNotEmpty)
                      Center(
                        child: Text(
                          email,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Center(child: Text(bio, textAlign: TextAlign.center)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _stat('ผู้ติดตาม', followers.length),
                        _stat('กำลังติดตาม', following.length),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _actions(name, bio, photoUrl, isFollowing),
                    const SizedBox(height: 20),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'โพสต์',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    _postsSection(),
                    if (_isMe) ...[
                      const SizedBox(height: 30),
                      const Divider(),
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
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final Post post;
  const _PostTile({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.content.isNotEmpty) Text(post.content),
            if (post.mediaUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppImage(
                  src: post.mediaUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorHeight: 120,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  formatRelativeTime(post.createdAt),
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const Spacer(),
                const Icon(Icons.thumb_up, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  '${post.likeCount}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
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
