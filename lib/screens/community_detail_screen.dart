import '../widgets/moderation_banner.dart';
import 'dart:async';
import '../widgets/profile_link.dart';
import '../widgets/privacy_icon.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/reactions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../models/community_model.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/community_service.dart';
import '../services/storage_service.dart';
import '../services/video_upload_service.dart';
import '../widgets/post_media.dart';
import '../widgets/user_avatar.dart';
import '../widgets/mention_text.dart';
import '../widgets/mention_text_field.dart';
import '../services/mention_service.dart';
import '../utils/mention.dart';
import 'community_moderation_screen.dart';
import 'members_list_screen.dart';
import '../widgets/report_dialog.dart';
import '../widgets/share_post_sheet.dart';
import '../services/chat_service.dart';

class CommunityDetailScreen extends StatefulWidget {
  final Community community;
  const CommunityDetailScreen({required this.community, super.key});
  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  final _uid = AuthService().currentUser?.uid ?? '';
  final _service = CommunityService();
  final _text = MentionController();
  late final MentionScope _mentionScope = MentionScope.community(
    widget.community.id,
    _uid,
  );
  final List<Uint8List> _images = []; // เลือกได้หลายรูป (สูงสุด maxPostImages)
  Uint8List? _videoBytes;
  String? _videoName;
  bool _busy = false;
  bool _banned = false; // ผู้ใช้นี้ถูกแบนจากชุมชนนี้หรือไม่
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _bannedSub;

  @override
  void initState() {
    super.initState();
    // ถ้า rules ยังไม่ได้ deploy (อ่านเอกสารแบนไม่ได้) จะถือว่าไม่ถูกแบนและไม่ crash
    _bannedSub = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.community.id)
        .collection('banned')
        .doc(_uid)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _banned = snap.exists);
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _bannedSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      await _service.join(widget.community, _uid);
      _message(
        widget.community.privacy == 'private'
            ? 'ส่งคำขอเข้าร่วมแล้ว'
            : 'เข้าร่วมชุมชนแล้ว',
      );
    } catch (e) {
      _message('เข้าร่วมไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty && _images.isEmpty && _videoBytes == null)
      return;
    final encodedText = _text.encoded;
    setState(() => _busy = true);
    try {
      String? mediaUrl;
      String? mediaType;
      var moreMediaUrls = <String>[];
      if (_images.isNotEmpty) {
        final urls = await StorageService().uploadPostImagesBytes(
          images: _images,
          uid: _uid,
        );
        mediaUrl = urls
            .first; // รูปแรก = mediaUrl เดิม, รูปที่เหลือเก็บใน moreMediaUrls
        moreMediaUrls = urls.sublist(1);
        mediaType = 'image';
      } else if (_videoBytes != null) {
        mediaUrl = await VideoUploadService().uploadVideoBytes(
          bytes: _videoBytes!,
          filename: _videoName ?? 'community-video.mp4',
        );
        mediaType = 'video';
      }
      await _service.createPost(
        communityId: widget.community.id,
        authorId: _uid,
        text: encodedText,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        moreMediaUrls: moreMediaUrls,
      );
      _text.clear();
      if (mounted)
        setState(() {
          _images.clear();
          _videoBytes = null;
          _videoName = null;
        });
    } catch (e) {
      _message('โพสต์ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage() async {
    final remaining = StorageService.maxPostImages - _images.length;
    if (remaining <= 0) {
      _message(
        'เลือกรูปได้ไม่เกิน ${StorageService.maxPostImages} รูปต่อโพสต์',
      );
      return;
    }
    try {
      // pickMultiImage ต้องมี limit >= 2 จึงใช้ pickImage ตอนเหลือที่ว่างรูปเดียว
      final List<XFile> picked;
      if (remaining == 1) {
        final one = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 640,
          maxHeight: 640,
          imageQuality: 55,
        );
        picked = one == null ? const [] : [one];
      } else {
        picked = await ImagePicker().pickMultiImage(
          maxWidth: 640,
          maxHeight: 640,
          imageQuality: 55,
          limit: remaining,
        );
      }
      if (picked.isEmpty) return;
      // บางแพลตฟอร์ม (เช่น เว็บ) ไม่สนใจ limit จึงตัดส่วนเกินทิ้งเอง
      final added = <Uint8List>[
        for (final file in picked.take(remaining)) await file.readAsBytes(),
      ];
      final next = [..._images, ...added];
      final error = StorageService.validatePostImages(next);
      if (error != null) {
        _message(error);
        return;
      }
      if (picked.length > remaining) {
        _message(
          'เลือกรูปได้ไม่เกิน ${StorageService.maxPostImages} รูปต่อโพสต์ '
          '(ใช้ $remaining รูปแรกที่เลือก)',
        );
      }
      if (mounted)
        setState(() {
          _images
            ..clear()
            ..addAll(next);
          _videoBytes = null;
          _videoName = null;
        });
    } catch (e) {
      _message('เลือกรูปไม่สำเร็จ: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: VideoUploadService.maxSeconds),
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > VideoUploadService.maxBytes)
        throw Exception(
          'วิดีโอต้องไม่เกิน ${VideoUploadService.maxBytes ~/ (1024 * 1024)} MB',
        );
      if (mounted)
        setState(() {
          _videoBytes = bytes;
          _videoName = file.name;
          _images.clear();
        });
    } catch (e) {
      _message('เลือกวิดีโอไม่สำเร็จ: $e');
    }
  }

  Future<void> _report(String postId, String authorId) => showReportFlow(
    context,
    title: 'รายงานโพสต์ถึงผู้ดูแลชุมชน',
    customSubmit: (reason, details) => _service.reportContent(
      communityId: widget.community.id,
      postId: postId,
      reporterId: _uid,
      reason: reason,
      details: details,
      reportedUid: authorId,
    ),
  );

  Future<bool> _confirmDanger(
    String title,
    String message,
    String okLabel,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _leaveCommunity() async {
    if (!await _confirmDanger(
      'ออกจากชุมชน?',
      'คุณจะไม่ได้เป็นสมาชิกและโพสต์ในชุมชนนี้ไม่ได้ (ชุมชนส่วนตัวต้องขอเข้าร่วมใหม่)',
      'ออกจากชุมชน',
    )) {
      return;
    }
    try {
      await _service.leave(widget.community.id, _uid);
      if (!mounted) return;
      _message('ออกจากชุมชนแล้ว');
      if (widget.community.privacy == 'private') Navigator.pop(context);
    } catch (e) {
      _message('ออกจากชุมชนไม่สำเร็จ: $e');
    }
  }

  Future<void> _deleteCommunity() async {
    if (!await _confirmDanger(
      'ลบชุมชนนี้ถาวร?',
      'ชุมชน โพสต์ คอมเมนต์ และสมาชิกทั้งหมดจะถูกลบและกู้คืนไม่ได้',
      'ลบชุมชน',
    )) {
      return;
    }
    final nav = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    try {
      await _service.deleteCommunity(widget.community.id, _uid);
      nav.pop(); // ปิด loading
      nav.pop(); // ออกจากหน้าชุมชน
    } catch (e) {
      nav.pop();
      _message('ลบชุมชนไม่สำเร็จ: $e');
    }
  }

  Future<void> _editPost(String postId, String oldText) async {
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => MentionControllerScope(
        encoded: oldText,
        builder: (_, controller) => AlertDialog(
          title: const Text('แก้ไขโพสต์'),
          content: MentionTextField(
            controller: controller,
            scope: _mentionScope,
            maxLines: 5,
            maxLength: 5000,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.encoded),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (newText != null) {
      try {
        await _service.editPost(
          communityId: widget.community.id,
          postId: postId,
          text: newText,
        );
      } catch (e) {
        _message('แก้ไขโพสต์ไม่สำเร็จ: $e');
      }
    }
  }

  void _openComments({
    required String postId,
    required String postOwnerId,
    required bool canModerate,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CommunityCommentsSheet(
        communityId: widget.community.id,
        postId: postId,
        postOwnerId: postOwnerId,
        canDeleteOthers: canModerate,
        scope: _mentionScope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final communityRef = FirebaseFirestore.instance
        .collection('communities')
        .doc(widget.community.id);
    final memberRef = communityRef.collection('members').doc(_uid);
    final requestRef = communityRef.collection('joinRequests').doc(_uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: memberRef.snapshots(),
      builder: (context, memberSnap) {
        final membership = memberSnap.data?.data();
        final isMember = membership != null;
        final role = membership?['role'] as String? ?? 'member';
        final canModerate = role == 'owner' || role == 'moderator';
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.community.name),
            actions: [
              if (canModerate)
                IconButton(
                  tooltip: 'เครื่องมือผู้ดูแล',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityModerationScreen(
                        community: widget.community,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'report') {
                    showReportFlow(
                      context,
                      title: 'รายงานชุมชน',
                      targetType: 'community',
                      targetId: widget.community.id,
                      reportedUid: widget.community.ownerId,
                      contextId: widget.community.id,
                    );
                  }
                  if (value == 'leave') _leaveCommunity();
                  if (value == 'delete') _deleteCommunity();
                },
                itemBuilder: (_) => [
                  if (isMember && role != 'owner')
                    const PopupMenuItem(
                      value: 'leave',
                      child: Text('ออกจากชุมชน'),
                    ),
                  if (_uid == widget.community.ownerId)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        'ลบชุมชน',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  if (_uid != widget.community.ownerId)
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('รายงานชุมชน'),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.community.privacy == 'private'
                              ? Icons.lock_outline
                              : Icons.public,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.community.privacy == 'private'
                              ? 'ชุมชนส่วนตัว'
                              : 'ชุมชนสาธารณะ',
                        ),
                        const Spacer(),
                        if (!isMember && widget.community.privacy == 'private')
                          const Text(
                            'เข้าร่วมเพื่อดูสมาชิก',
                            style: TextStyle(color: Colors.black54),
                          )
                        else
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: communityRef
                                .collection('members')
                                .snapshots(),
                            builder: (context, snap) => TextButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MembersListScreen(
                                    title: 'สมาชิก ${widget.community.name}',
                                    members: communityRef
                                        .collection('members')
                                        .snapshots()
                                        .map(
                                          (s) => s.docs
                                              .map(
                                                (d) => MemberEntry(
                                                  d.id,
                                                  d.data()['role'] as String? ??
                                                      'member',
                                                ),
                                              )
                                              .toList(),
                                        ),
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.people_outline, size: 18),
                              label: Text('${snap.data?.size ?? 0} สมาชิก'),
                            ),
                          ),
                      ],
                    ),
                    if (widget.community.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(widget.community.description),
                      ),
                  ],
                ),
              ),
              if (_banned)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.block,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'คุณถูกแบนจากชุมชนนี้ จึงไม่สามารถเข้าร่วม ดู หรือโพสต์ได้',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isMember && !_banned)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: requestRef.snapshots(),
                  builder: (context, requestSnap) {
                    final requested = requestSnap.data?.exists ?? false;
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy
                              ? null
                              : requested
                              ? () => _service.cancelRequest(
                                  widget.community.id,
                                  _uid,
                                )
                              : _join,
                          icon: Icon(
                            requested
                                ? Icons.hourglass_top
                                : Icons.group_add_outlined,
                          ),
                          label: Text(
                            requested
                                ? 'ยกเลิกคำขอเข้าร่วม'
                                : widget.community.privacy == 'private'
                                ? 'ขอเข้าร่วมชุมชน'
                                : 'เข้าร่วมชุมชน',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (isMember)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          UserAvatar(uid: _uid),
                          const SizedBox(width: 8),
                          Expanded(
                            child: MentionTextField(
                              controller: _text,
                              scope: _mentionScope,
                              maxLength: 5000,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                hintText:
                                    'เขียนโพสต์ในชุมชน (พิมพ์ @ เพื่อแท็ก)',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _busy ? null : _post,
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                      if (_images.isNotEmpty)
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _images.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) => Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _images[i],
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                    tooltip: 'ลบรูปที่ ${i + 1}',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.close,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black45,
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _images.removeAt(i),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_videoName != null)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.videocam),
                          title: Text(
                            _videoName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            onPressed: () => setState(() {
                              _videoBytes = null;
                              _videoName = null;
                            }),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed:
                                _busy ||
                                    _images.length >=
                                        StorageService.maxPostImages
                                ? null
                                : _pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(
                              _images.isEmpty
                                  ? 'รูป'
                                  : 'รูป (${_images.length}/${StorageService.maxPostImages})',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _busy ? null : _pickVideo,
                            icon: const Icon(Icons.video_library_outlined),
                            label: const Text('วิดีโอ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _banned
                    ? const SizedBox.shrink()
                    : !isMember && widget.community.privacy == 'private'
                    ? const Center(
                        child: Text(
                          'โพสต์จะแสดงหลังจากได้รับอนุมัติเข้าร่วมชุมชน',
                        ),
                      )
                    : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: communityRef
                            .collection('posts')
                            .orderBy('createdAt', descending: true)
                            .limit(60)
                            .snapshots(),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            final denied = '${snap.error}'.contains(
                              'permission-denied',
                            );
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  denied
                                      ? 'คุณไม่มีสิทธิ์ดูโพสต์ของชุมชนนี้'
                                      : 'โหลดโพสต์ชุมชนไม่สำเร็จ: ${snap.error}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          if (!snap.hasData)
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          if (snap.data!.docs.isEmpty)
                            return const Center(
                              child: Text('ชุมชนนี้ยังไม่มีโพสต์'),
                            );
                          // โพสต์ที่ถูกซ่อนโดยระบบดูแลโพสต์: เจ้าของโพสต์และผู้ดูแลชุมชนยังเห็น คนอื่นไม่เห็น
                          final visibleDocs = snap.data!.docs
                              .where(
                                (d) =>
                                    canModerate ||
                                    !moderationHiddenFor(d.data(), _uid),
                              )
                              .toList();
                          return ListView.builder(
                            itemCount: visibleDocs.length,
                            itemBuilder: (context, index) {
                              final doc = visibleDocs[index];
                              final data = doc.data();
                              final authorId =
                                  data['authorId'] as String? ?? '';
                              return Card(
                                margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (moderationHiddenNow(data) &&
                                          authorId == _uid)
                                        HiddenPostBanner.fromData(
                                          data,
                                          onEdit: () => _editPost(
                                            doc.id,
                                            data['text'] as String? ?? '',
                                          ),
                                        )
                                      else if (moderationHiddenNow(data))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.visibility_off,
                                                size: 16,
                                                color: Colors.orange.shade800,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'โพสต์นี้ถูกซ่อนจากสมาชิก (เห็นเฉพาะผู้ดูแล)',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: Colors.orange.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Row(
                                        children: [
                                          UserAvatar(
                                            uid: authorId,
                                            radius: 18,
                                            tappable: true,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                ProfileLink(
                                                  uid: authorId,
                                                  child: _MemberName(
                                                    uid: authorId,
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    Text(
                                                      _communityTime(
                                                        data['createdAt']
                                                            as Timestamp?,
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    PrivacyIcon(
                                                      widget.community.privacy,
                                                      scope: 'ชุมชน',
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (data['isPinned'] == true)
                                            const Icon(
                                              Icons.push_pin_outlined,
                                              size: 18,
                                            ),
                                          PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'edit')
                                                _editPost(
                                                  doc.id,
                                                  data['text'] as String? ?? '',
                                                );
                                              if (value == 'delete')
                                                _service.deletePost(
                                                  widget.community.id,
                                                  doc.id,
                                                );
                                              if (value == 'pin')
                                                _service.pinPost(
                                                  widget.community.id,
                                                  doc.id,
                                                  data['isPinned'] != true,
                                                );
                                              if (value == 'report')
                                                _report(doc.id, authorId);
                                            },
                                            itemBuilder: (_) => [
                                              if (authorId == _uid)
                                                const PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('แก้ไขโพสต์'),
                                                ),
                                              if (canModerate ||
                                                  authorId == _uid)
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('ลบโพสต์'),
                                                ),
                                              if (canModerate)
                                                PopupMenuItem(
                                                  value: 'pin',
                                                  child: Text(
                                                    data['isPinned'] == true
                                                        ? 'เลิกปักหมุด'
                                                        : 'ปักหมุด',
                                                  ),
                                                ),
                                              if (isMember && authorId != _uid)
                                                const PopupMenuItem(
                                                  value: 'report',
                                                  child: Text('รายงาน'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if ((data['text'] as String? ?? '')
                                          .isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: MentionText(
                                            data['text'] as String? ?? '',
                                          ),
                                        ),
                                      if (data['mediaUrl'] is String)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: PostMedia(
                                            url: data['mediaUrl'] as String,
                                            type: data['mediaType'] as String?,
                                            moreUrls: Post.urlList(
                                              data['moreMediaUrls'],
                                            ),
                                          ),
                                        ),
                                      CommunityPostActions(
                                        communityId: widget.community.id,
                                        postId: doc.id,
                                        uid: _uid,
                                        text: data['text'] as String? ?? '',
                                        mediaUrl: data['mediaUrl'] as String?,
                                        likeCount:
                                            (data['likeCount'] as num?)
                                                ?.toInt() ??
                                            0,
                                        dislikeCount:
                                            (data['dislikeCount'] as num?)
                                                ?.toInt() ??
                                            0,
                                        onComments: () => _openComments(
                                          postId: doc.id,
                                          postOwnerId: authorId,
                                          canModerate: canModerate,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MemberName extends StatelessWidget {
  final String uid;
  const _MemberName({required this.uid});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) => Text(
          snap.data?.data()?['name'] as String? ?? 'สมาชิก',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
}

String _communityTime(Timestamp? timestamp) {
  if (timestamp == null) return 'เพิ่งโพสต์';
  final age = DateTime.now().difference(timestamp.toDate());
  if (age.inSeconds < 60) return 'เมื่อสักครู่';
  if (age.inMinutes < 60) return '${age.inMinutes} นาทีที่แล้ว';
  if (age.inHours < 24) return '${age.inHours} ชั่วโมงที่แล้ว';
  if (age.inDays < 7) return '${age.inDays} วันที่แล้ว';
  final date = timestamp.toDate();
  return '${date.day}/${date.month}/${date.year}';
}

class CommunityPostActions extends StatelessWidget {
  final String communityId;
  final String postId;
  final String uid;
  final String text;
  final String? mediaUrl;
  final int likeCount;
  final int dislikeCount;
  final VoidCallback onComments;
  const CommunityPostActions({
    required this.communityId,
    required this.postId,
    required this.uid,
    required this.text,
    required this.mediaUrl,
    required this.likeCount,
    required this.dislikeCount,
    required this.onComments,
  });

  Future<void> _react(BuildContext context, String type) async {
    try {
      await CommunityService().setReaction(
        communityId: communityId,
        postId: postId,
        uid: uid,
        type: type,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ทำรายการไม่สำเร็จ: $e')));
    }
  }

  Future<void> _share(BuildContext context) async {
    // ชุมชนส่วนตัว: ส่งต่อได้เฉพาะเป็นลิงก์ในแชท/กลุ่ม (ผู้รับต้องขอเข้าร่วมชุมชนก่อนจึงจะดูได้)
    var privateCommunity = true;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('communities')
          .doc(communityId)
          .get();
      privateCommunity = (doc.data()?['privacy'] ?? 'public') == 'private';
    } catch (_) {}
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('ส่งในแชท / กลุ่ม'),
              onTap: () => Navigator.pop(sheetContext, 'chat'),
            ),
            if (!privateCommunity)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('แชร์ผ่านแอปอื่น'),
                onTap: () => Navigator.pop(sheetContext, 'external'),
              )
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'โพสต์นี้อยู่ในชุมชนส่วนตัว ส่งได้เฉพาะในแชท/กลุ่ม และผู้รับต้องเป็นสมาชิกชุมชนจึงจะดูเนื้อหาได้',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'chat') {
      await showSharePostToChat(
        context,
        postRef: ChatService.postRef(
          kind: 'community_post',
          postId: postId,
          communityId: communityId,
        ),
      );
      return;
    }
    final parts = <String>[
      if (text.trim().isNotEmpty) Mention.plain(text).trim(),
      if (mediaUrl != null && !mediaUrl!.startsWith('data:')) mediaUrl!,
      'โพสต์นี้แชร์จากชุมชนใน Social',
    ];
    try {
      await SharePlus.instance.share(
        ShareParams(text: parts.join('\n\n'), title: 'แชร์โพสต์'),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('แชร์โพสต์ไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = CommunityService();
    final post = service.postDocument(communityId, postId);
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              if (likeCount > 0) ...[
                Icon(Icons.thumb_up, size: 14, color: primary),
                const SizedBox(width: 4),
                Text('$likeCount', style: const TextStyle(fontSize: 12)),
              ],
              if (dislikeCount > 0) ...[
                if (likeCount > 0) const SizedBox(width: 10),
                const Icon(Icons.thumb_down, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text('$dislikeCount', style: const TextStyle(fontSize: 12)),
              ],
              const Spacer(),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: service.comments(communityId, postId),
                builder: (context, snap) => Text(
                  '${snap.data?.size ?? 0} คอมเมนต์',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        ReactionSummary(stream: service.reactions(communityId, postId)),
        const Divider(height: 14),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: post.collection('reactions').doc(uid).snapshots(),
          builder: (context, snap) {
            final type = snap.data?.data()?['type'] as String?;
            final selected = reactionOptionFor(type);
            return Row(
              children: [
                Expanded(
                  child: PostActionButton(
                    icon: Icons.thumb_up,
                    label: selected?.label ?? 'Like',
                    emoji: selected == null || selected.type == 'like'
                        ? null
                        : selected.emoji,
                    active: type != null && type != 'dislike',
                    onTap: () => _react(context, 'like'),
                    onLongPress: () => showReactionPicker(
                      context,
                      (value) => _react(context, value),
                    ),
                  ),
                ),
                Expanded(
                  child: PostActionButton(
                    icon: Icons.thumb_down,
                    label: 'Dislike',
                    active: type == 'dislike',
                    onTap: () => _react(context, 'dislike'),
                  ),
                ),
                Expanded(
                  child: PostActionButton(
                    icon: Icons.comment_outlined,
                    label: 'Comment',
                    onTap: onComments,
                  ),
                ),
                Expanded(
                  child: PostActionButton(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    onTap: () => _share(context),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// เปิดหน้าต่างคอมเมนต์ของโพสต์ในชุมชน (ใช้ซ้ำได้จากหน้าอื่น เช่น โปรไฟล์)
void showCommunityPostComments(
  BuildContext context, {
  required String communityId,
  required String postId,
  required String postOwnerId,
  bool canDeleteOthers = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CommunityCommentsSheet(
      communityId: communityId,
      postId: postId,
      postOwnerId: postOwnerId,
      canDeleteOthers: canDeleteOthers,
      scope: MentionScope.community(
        communityId,
        AuthService().currentUser?.uid ?? '',
      ),
    ),
  );
}

class _CommunityCommentsSheet extends StatefulWidget {
  final String communityId;
  final String postId;
  final String postOwnerId;
  final bool canDeleteOthers;
  final MentionScope scope;
  const _CommunityCommentsSheet({
    required this.communityId,
    required this.postId,
    required this.postOwnerId,
    required this.canDeleteOthers,
    required this.scope,
  });

  @override
  State<_CommunityCommentsSheet> createState() =>
      _CommunityCommentsSheetState();
}

class _CommunityCommentsSheetState extends State<_CommunityCommentsSheet> {
  final _uid = AuthService().currentUser?.uid ?? '';
  final _text = MentionController();
  final _service = CommunityService();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_text.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _service.addComment(
        communityId: widget.communityId,
        postId: widget.postId,
        authorId: _uid,
        text: _text.encoded,
      );
      _text.clear();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ส่งคอมเมนต์ไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(String commentId, String oldText) async {
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => MentionControllerScope(
        encoded: oldText,
        builder: (_, controller) => AlertDialog(
          title: const Text('แก้ไขคอมเมนต์'),
          content: MentionTextField(
            controller: controller,
            scope: widget.scope,
            maxLength: 2000,
            maxLines: 4,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.encoded),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (newText != null) {
      await _service.editComment(
        communityId: widget.communityId,
        postId: widget.postId,
        commentId: commentId,
        text: newText,
      );
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.of(context).size.height * .78,
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'คอมเมนต์',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _service.comments(widget.communityId, widget.postId),
            builder: (context, snap) {
              if (snap.hasError)
                return Center(
                  child: Text('โหลดคอมเมนต์ไม่สำเร็จ: ${snap.error}'),
                );
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty)
                return const Center(child: Text('ยังไม่มีคอมเมนต์'));
              return ListView(
                children: snap.data!.docs.map((doc) {
                  final data = doc.data();
                  final authorId = data['authorId'] as String? ?? '';
                  return ListTile(
                    leading: UserAvatar(
                      uid: authorId,
                      radius: 18,
                      tappable: true,
                    ),
                    title: ProfileLink(
                      uid: authorId,
                      child: _MemberName(uid: authorId),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MentionText(data['text'] as String? ?? ''),
                        Text(
                          _communityTime(data['createdAt'] as Timestamp?),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    trailing:
                        authorId == _uid ||
                            widget.canDeleteOthers ||
                            widget.postOwnerId == _uid
                        ? PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit')
                                _edit(doc.id, data['text'] as String? ?? '');
                              if (value == 'delete')
                                _service.deleteComment(
                                  communityId: widget.communityId,
                                  postId: widget.postId,
                                  commentId: doc.id,
                                );
                            },
                            itemBuilder: (_) => [
                              if (authorId == _uid)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('แก้ไข'),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('ลบ'),
                              ),
                            ],
                          )
                        : PopupMenuButton<String>(
                            onSelected: (_) => showReportFlow(
                              context,
                              title: 'รายงานคอมเมนต์ถึงผู้ดูแลชุมชน',
                              customSubmit: (reason, details) =>
                                  _service.reportContent(
                                    communityId: widget.communityId,
                                    postId: widget.postId,
                                    commentId: doc.id,
                                    reporterId: _uid,
                                    reason: reason,
                                    details: details,
                                    reportedUid: authorId,
                                  ),
                            ),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'report',
                                child: Text('รายงานคอมเมนต์'),
                              ),
                            ],
                          ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: MentionTextField(
                    controller: _text,
                    scope: widget.scope,
                    suggestionsAbove: true,
                    maxLength: 2000,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'เขียนคอมเมนต์ (พิมพ์ @ เพื่อแท็ก)',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// หน้าเปิดโพสต์ของชุมชนโพสต์เดียว (ใช้เมื่อกดแจ้งเตือนที่ถูกแท็ก/ถูกใจ/คอมเมนต์)
class CommunityPostScreen extends StatefulWidget {
  final String communityId;
  final String postId;

  /// true = เปิดหน้าต่างคอมเมนต์ทันที
  final bool openComments;
  const CommunityPostScreen({
    required this.communityId,
    required this.postId,
    this.openComments = false,
    super.key,
  });

  @override
  State<CommunityPostScreen> createState() => _CommunityPostScreenState();
}

class _CommunityPostScreenState extends State<CommunityPostScreen> {
  final _uid = AuthService().currentUser?.uid ?? '';
  late final MentionScope _scope = MentionScope.community(
    widget.communityId,
    _uid,
  );
  late final DocumentReference<Map<String, dynamic>> _communityRef =
      FirebaseFirestore.instance
          .collection('communities')
          .doc(widget.communityId);
  bool _commentsOpened = false;

  void _openComments(String postOwnerId, bool canModerate) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CommunityCommentsSheet(
        communityId: widget.communityId,
        postId: widget.postId,
        postOwnerId: postOwnerId,
        canDeleteOthers: canModerate,
        scope: _scope,
      ),
    );
  }

  Widget _message(String text) => Scaffold(
    appBar: AppBar(title: const Text('โพสต์ในชุมชน')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    ),
  );

  Future<void> _openCommunity() async {
    final nav = Navigator.of(context);
    final doc = await _communityRef.get();
    if (!doc.exists || !mounted) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) =>
            CommunityDetailScreen(community: Community.fromDoc(doc)),
      ),
    );
  }

  /// ดูโพสต์ไม่ได้ (ชุมชนส่วนตัวที่ยังไม่เป็นสมาชิก / ถูกแบน / โพสต์ไม่มีอยู่)
  /// พาไปหน้าชุมชนเพื่อขอเข้าร่วมได้
  Widget _lockedMessage() => Scaffold(
    appBar: AppBar(title: const Text('โพสต์ในชุมชน')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.black38),
            const SizedBox(height: 12),
            const Text(
              'คุณยังไม่มีสิทธิ์ดูโพสต์นี้\nหากเป็นชุมชนส่วนตัว ต้องขอเข้าร่วมและรอการอนุมัติก่อน',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openCommunity,
              icon: const Icon(Icons.group_outlined),
              label: const Text('ไปที่ชุมชน'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _communityRef.collection('members').doc(_uid).snapshots(),
      builder: (context, memberSnap) {
        final role = memberSnap.data?.data()?['role'] as String? ?? 'member';
        final canModerate = role == 'owner' || role == 'moderator';
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _communityRef
              .collection('posts')
              .doc(widget.postId)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _lockedMessage();
            }
            if (!snap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final data = snap.data!.data();
            if (data == null) return _message('โพสต์นี้ถูกลบแล้ว');
            final authorId = data['authorId'] as String? ?? '';
            if (widget.openComments && !_commentsOpened) {
              _commentsOpened = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _openComments(authorId, canModerate);
              });
            }
            return Scaffold(
              appBar: AppBar(
                title: const Text('โพสต์ในชุมชน'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final doc = await _communityRef.get();
                      if (!doc.exists || !mounted) return;
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => CommunityDetailScreen(
                            community: Community.fromDoc(doc),
                          ),
                        ),
                      );
                    },
                    child: const Text('ไปที่ชุมชน'),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              UserAvatar(
                                uid: authorId,
                                radius: 18,
                                tappable: true,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ProfileLink(
                                  uid: authorId,
                                  child: _MemberName(uid: authorId),
                                ),
                              ),
                            ],
                          ),
                          if ((data['text'] as String? ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: MentionText(data['text'] as String? ?? ''),
                            ),
                          if (data['mediaUrl'] is String)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: PostMedia(
                                url: data['mediaUrl'] as String,
                                type: data['mediaType'] as String?,
                                moreUrls: Post.urlList(data['moreMediaUrls']),
                              ),
                            ),
                          CommunityPostActions(
                            communityId: widget.communityId,
                            postId: widget.postId,
                            uid: _uid,
                            text: data['text'] as String? ?? '',
                            mediaUrl: data['mediaUrl'] as String?,
                            likeCount:
                                (data['likeCount'] as num?)?.toInt() ?? 0,
                            dislikeCount:
                                (data['dislikeCount'] as num?)?.toInt() ?? 0,
                            onComments: () =>
                                _openComments(authorId, canModerate),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
