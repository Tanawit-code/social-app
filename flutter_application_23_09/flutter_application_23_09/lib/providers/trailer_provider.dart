import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/movie.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final trailerProvider = FutureProvider.family<Trailer?, int>((ref, movieId) async {
  final response = await Dio().get(
    "https://api.themoviedb.org/3/movie/$movieId/videos",
    queryParameters: {"api_key": dotenv.env['TMDB_API_KEY'], "language": "en-US"},
  );

  final results = response.data['results'] as List;
  
  // หา trailer ที่มาจาก YouTube
  final trailers = results
      .map((json) => Trailer.fromJson(json))
      .where((t) => t.site == "YouTube" && t.type == "Trailer")
      .toList();

  return trailers.isNotEmpty ? trailers.first : null;
});
