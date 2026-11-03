import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/page_service.dart';
import '../services/post_service.dart';
import 'home_feed_screen.dart' show PostCard;

/// เปิดโพสต์เดียว (โพสต์ฟีด/โพสต์ในเพจ) — ใช้เมื่อกดแจ้งเตือนที่ถูกแท็ก/ถูกใจ/คอมเมนต์
class PostDetailScreen extends StatelessWidget {
  final String postId;

  /// true = เปิดหน้าต่างความคิดเห็นทันที (เช่น ถูกแท็กในคอมเมนต์)
  final bool openComments;
  const PostDetailScreen({
    required this.postId,
    this.openComments = false,
    super.key,
  });

  Widget _message(String text) => Scaffold(
    appBar: AppBar(title: const Text('โพสต์')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final uid = AuthService().currentUser?.uid ?? '';
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _message('ไม่พบโพสต์นี้ หรือคุณไม่มีสิทธิ์ดูโพสต์นี้');
        }
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.data!.exists) return _message('โพสต์นี้ถูกลบแล้ว');
        final post = Post.fromDoc(snap.data!);
        return Scaffold(
          appBar: AppBar(title: const Text('โพสต์')),
          body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
            // เจ้าของ/ผู้ดูแลเพจลบโพสต์ของคนอื่นในเพจได้
            future: post.pageId == null
                ? Future.value(null)
                : FirebaseFirestore.instance
                      .collection('pages')
                      .doc(post.pageId)
                      .get(),
            builder: (context, pageSnap) {
              if (post.pageId != null &&
                  pageSnap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  PostCard(
                    post: post,
                    currentUid: uid,
                    postService: PostService(),
                    canModerate: PageService.canModerate(
                      pageSnap.data?.data(),
                      uid,
                    ),
                    autoOpenComments: openComments,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
