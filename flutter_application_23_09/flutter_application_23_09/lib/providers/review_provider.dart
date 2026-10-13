import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dio_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/review.dart';

final reviewsProvider = FutureProvider.family<List<Review>, int>((ref, movieId) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get(
    "/movie/$movieId/reviews",
    queryParameters: {
      "api_key": dotenv.env['TMDB_API_KEY'],
      "language": "en-US",
    },
  );

  final results = response.data['results'] as List<dynamic>;
  return results.map((json) => Review.fromJson(json)).toList();
});
