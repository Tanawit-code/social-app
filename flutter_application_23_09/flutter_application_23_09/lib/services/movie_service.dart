import 'package:dio/dio.dart'; // ใช้ Dio สำหรับเรียก API
import '../models/movie.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Service class สำหรับดึงข้อมูลจาก API
class MovieService {
  final dio = Dio(); // object สำหรับเรียก API
  final String apiKey = dotenv.env['TMDB_API_KEY'] ?? ''; // กุญแจ API (ควรเก็บใน .env)

  // ดึงข้อมูลหนังยอดนิยมจาก TMDB API
  Future<List<Movie>> fetchMovies() async {
    try {
      final res = await dio.get(
        'https://api.themoviedb.org/3/movie/popular',
        queryParameters: {
          'api_key': apiKey,
          'language': 'th-TH',
          'page': 1,
          'region': "TH",
        },
      );
      // แปลงผลลัพธ์จาก JSON -> List<Movie>
      return (res.data['results'] as List)
          .map((e) => Movie.fromJson(e))
          .toList();
    } catch (e) {
      // ถ้ามี error ให้โยนต่อไปให้ UI จัดการ
      throw Exception("Failed to load movies: $e");
    }
  }
}



