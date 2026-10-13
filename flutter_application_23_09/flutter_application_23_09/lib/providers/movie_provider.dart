import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dio_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/movie.dart';

final moviesProvider = FutureProvider<List<Movie>>((ref) async {
  final dio = ref.watch(dioProvider);
  final apiKey = dotenv.env['TMDB_API_KEY']?.trim();

  if (apiKey == null || apiKey.isEmpty) {
    throw Exception(
      'ยังไม่มี TMDB API key: ใส่ค่า TMDB_API_KEY ในไฟล์ .env แล้วรันแอปใหม่',
    );
  }

  final response = await dio.get(
    "/movie/now_playing",
    queryParameters: {
      "api_key": apiKey,
      "language": "th-TH",
      "region": "TH",
    },
  );

  final results = response.data['results'] as List<dynamic>;
  return results.map((json) => Movie.fromJson(json)).toList();
});
