import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../services/auth_service.dart';
import '../services/post_service.dart';
import '../widgets/post_media.dart';
import '../widgets/user_avatar.dart';
import 'home_feed_screen.dart' show AuthorName;

class ReelsScreen extends StatelessWidget {
  const ReelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService().currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Reels')),
      body: StreamBuilder<List<Post>>(
        stream: PostService().feedStream(viewerId: uid, limit: 100),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(
              child: Text('โหลด Reels ไม่สำเร็จ: ${snapshot.error}'),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final reels = snapshot.data!
              .where((post) => post.mediaType == 'video')
              .toList();
          if (reels.isEmpty)
            return const Center(
              child: Text(
                'ยังไม่มี Reel ในฟีด\nสร้างโพสต์วิดีโอแล้วเลือก “แชร์เป็น Reel”',
                textAlign: TextAlign.center,
              ),
            );
          return PageView.builder(
            scrollDirection: Axis.vertical,
            itemCount: reels.length,
            itemBuilder: (context, index) {
              final reel = reels[index];
              return ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: PostMedia(
                        url: reel.mediaUrl ?? '',
                        type: reel.mediaType,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24 + MediaQuery.of(context).padding.bottom,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              UserAvatar(uid: reel.authorId, radius: 18),
                              const SizedBox(width: 8),
                              AuthorName(
                                uid: reel.authorId,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          if (reel.content.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                reel.content,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(color: Colors.black, blurRadius: 8),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: SafeArea(
                        child: Text(
                          '${index + 1}/${reels.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
