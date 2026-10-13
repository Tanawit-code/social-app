import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../models/movie.dart';
import '../providers/review_provider.dart';
import '../providers/trailer_provider.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  final Movie movie;
  const MovieDetailScreen({super.key, required this.movie});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  YoutubePlayerController? _controller;

  /*  ป้องกัน memory leak
      ใน statefulwidget นั้น เมื่อสถานะเดิมถูกเปลี่ยน จะหมายความว่า widget ได้ถูกยกเลิกหรือทำลาย (removed) ออกจาก widget tree ตามวงจรการทำงาน (life cycle) ของ stateful (ถูกสร้างขึ้น > แสดงผล > ถูกทำลาย)
      ซึ่ง widget เหล่านั้น เมื่อตอนที่ถูกสร้างขึ้นและเรียกใช้จะมีการใช้ทรัพยากร (resource) เช่น พื้นที่หน่วยความจำในแรม
      แต่เมื่อ life cycle จบลง โปรแกรมจะไม่ยอมคืนทรัพยากรในหน่วยความจำที่ได้ใช้ไปทำให้เกิดปัญหา memory leak ดังนั้นระบบปฏิบัติการจะไม่สามารถนำทรัพยากรที่ไม่ได้ถูกใช้แล้วไปใช้งานต่อไป (กินแรมมากยิ่งขึ้น)
      จากปัญหานี้ จึงต้องมีการเคลียร์ทรัพยากร (clean up) หลังจากที่ widget ถูกทำลายลง ด้วยคำสั่ง dispose()

      การเคลียร์ทรัพยากรจาก widget ต่างๆ เช่น
        - ปิด stream, VideoPlayer
        - ยกเลิก timer
        - dispose controller ต่างๆ เช่น TextEditingController, AnimationController, PageController



      StatefulWidget Life Cycle

      สร้าง widget ใหม่
        │
        ▼
  createState() ──► สร้าง State object
        │
        ▼
    initState() ──► เรียกครั้งเดียวตอนเริ่ม
        │
        ▼
    didChangeDependencies() ──► โหลด context, provider, inherited widget
        │
        ▼
       build() ──► วาด UI
        │
        ├──► setState() ──► trigger build() ใหม่
        │
        ▼
   didUpdateWidget() ──► เรียกเมื่อ widget ถูก rebuild
        │
        ▼
  deactivate() ──► widget ถูกถอดออกชั่วคราว
        │
        ▼
    dispose() ──► ล้าง resource (controller, stream, etc.)
        │
        ▼
 State object ถูกลบจาก memory
 
  */
  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reviewsAsync = ref.watch(reviewsProvider(widget.movie.id));
    final trailerAsync = ref.watch(trailerProvider(widget.movie.id));

    return trailerAsync.when(
      data: (trailer) {
        if (trailer == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.movie.title)),
            body: const Center(child: Text("No trailer available.")),
          );
        }

        // สร้าง controller แค่ครั้งเดียว
        _controller ??= YoutubePlayerController(
          initialVideoId: trailer.key,
          flags: const YoutubePlayerFlags(
            autoPlay: false,
            mute: false,
          ),
        );

        return YoutubePlayerBuilder(
          player: YoutubePlayer(
            controller: _controller!,
            showVideoProgressIndicator: true,
            progressIndicatorColor: Colors.amber,
          ),
          builder: (context, player) => Scaffold(
            appBar: AppBar(title: Text(widget.movie.title)),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // --- เรื่องย่อ ---
                  const Text("เรื่องย่อ",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.movie.overview.isNotEmpty
                            ? widget.movie.overview
                            : "No overview available.",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- ตัวอย่างหนัง (Trailer) ---
                  player,
                  const SizedBox(height: 16),

                  // --- โปสเตอร์หนัง ---
                  Image.network(
                      "https://image.tmdb.org/t/p/w500${widget.movie.posterPath}"),
                  const SizedBox(height: 16),

                  // --- คะแนนโหวต ---
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber),
                      const SizedBox(width: 8),
                      Text(
                        "${widget.movie.voteAverage.toStringAsFixed(1)}/10",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // --- Reviews ---
                  const Text("Reviews",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  reviewsAsync.when(
                    data: (reviews) {
                      if (reviews.isEmpty) {
                        return const Text("No reviews available.");
                      }
                      return Column(
                        children: reviews.map((review) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(review.author,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 5),
                                  Text(review.content),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const CircularProgressIndicator(),
                    error: (err, _) => Text("Error loading reviews: $err"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: Text(widget.movie.title)),
        body: Center(child: Text("Error loading trailer: $err")),
      ),
    );
  }
}

/*    // มีวิดีโอ แต่ไม่มี full screen


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../providers/review_provider.dart';
import '../providers/trailer_provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  final Movie movie;
  const MovieDetailScreen({super.key, required this.movie});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  late YoutubePlayerController _controller;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final reviewsAsync = ref.watch(reviewsProvider(widget.movie.id));
    final trailerAsync = ref.watch(trailerProvider(widget.movie.id));

    return Scaffold(
      appBar: AppBar(title: Text(widget.movie.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: 
        Column(
          children: [

            // เรื่องย่อ (movie overview)
            const Text("เรื่องย่อ", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(5)),
              ),
              elevation: 0,
              //color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.movie.overview.isNotEmpty
                      ? widget.movie.overview
                      : "No overview available.",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ตัวอย่างหนัง Trailer Youtube Player
            trailerAsync.when(
              data: (trailer) {
                if (trailer == null) {
                  return const Text("No trailer available.");
                }

                _controller = YoutubePlayerController(
                  initialVideoId: trailer.key,
                  flags: const YoutubePlayerFlags(
                    autoPlay: false,
                    mute: false,
                  ),
                );

                return  YoutubePlayerBuilder(
                  player: YoutubePlayer(
                    controller: _controller,
                    showVideoProgressIndicator: true,
                    progressIndicatorColor: Colors.amber,
                  ),
                  builder: (context, player) {
                    return Column(
                      children: [

                        player,

                        
                      ],
                    );
                  },
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, _) => Text("Error loading trailer: $err"),
            ),

            const SizedBox(height: 16),
            
            // โปสเตอร์หนัง (movie poster)
            Image.network("https://image.tmdb.org/t/p/w500${widget.movie.posterPath}"),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 8),
                Text("${widget.movie.voteAverage.toStringAsFixed(1)}/10", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ]
            ),
            const Text("Reviews", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            reviewsAsync.when(
              data: (reviews) {
                if (reviews.isEmpty) {
                  return const Text("No reviews available.");
                }
                return Column(
                  children: reviews.map((review) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(review.author, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text(review.content, style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, _) => Text("Error loading reviews: $err"),
            ),
          ],
        ),
      ),
    );
  }
}

*/

/* 
  // ไม่มีวิดีโอ


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import '../providers/review_provider.dart';
//import '../providers/movie_provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class MovieDetailScreen extends ConsumerWidget {
  final Movie movie;
  const MovieDetailScreen({super.key, required this.movie});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(reviewsProvider(movie.id));

    YoutubePlayerController controller = YoutubePlayerController(
      initialVideoId: 'd9erkpdh5o0',
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true,
      ),
      );
    

    return Scaffold(
      appBar: AppBar(title: Text(movie.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            // เรื่องย่อ (movie overview)
            const Text("เรื่องย่อ"),
            Card(
              child: Column(
                children: [
                  Text(movie.overview),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ตัวอย่างหนัง Trailer Youtube Player
            YoutubePlayer(
              controller: controller,
              showVideoProgressIndicator: true,
              progressIndicatorColor: Colors.amber,
            ),
            const SizedBox(height: 16),
            
            // โปสเตอร์หนัง (movie poster)
            Image.network("https://image.tmdb.org/t/p/w500${movie.posterPath}"),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 8),
                Text("${movie.voteAverage.toStringAsFixed(1)}/10", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ]
            ),
            const Text("Reviews", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            reviewsAsync.when(
              data: (reviews) {
                if (reviews.isEmpty) {
                  return const Text("No reviews available.");
                }
                return Column(
                  children: reviews.map((review) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(review.author, style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 5),
                            Text(review.content),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (err, _) => Text("Error loading reviews: $err"),
            ),
          ],
        ),
      ),
    );
  }
}

*/
