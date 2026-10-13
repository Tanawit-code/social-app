import 'package:flutter/material.dart';
import '../models/movie.dart';

// Card สำหรับแสดงหนังแต่ละเรื่อง
class MovieCard extends StatelessWidget {
  final Movie movie;
  const MovieCard({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3, // เงานิดหน่อย
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                "https://image.tmdb.org/t/p/w500${movie.posterPath}", // ประกอบ URL
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  // แสดง progress ระหว่างโหลดรูป
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image, size: 50), // ถ้าโหลดรูปไม่ได้
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              movie.title,
              maxLines: 1, // แสดงแค่บรรทัดเดียว
              overflow: TextOverflow.ellipsis, // ถ้ายาวเกินตัดด้วย ...
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
    );
  }
}
