class Movie {
  final int id;
  final String title;
  final String posterPath;
  final double voteAverage;
  final String overview;

  Movie({
    required this.id,
    required this.title,
    required this.posterPath,
    required this.voteAverage,
    required this.overview
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'],
      title: json['title'],
      posterPath: json['poster_path'] ?? '',
      voteAverage: (json['vote_average'] as num).toDouble(), // แปลงเป็น Double
      overview: json['overview'],
    );
  }

}

class Trailer {
  final String id;
  final String key;
  final String name;
  final String site;
  final String type;

  Trailer({
    required this.id,
    required this.key,
    required this.name,
    required this.site,
    required this.type,
  });

  factory Trailer.fromJson(Map<String, dynamic> json) {
    return Trailer(
      id: json['id'],
      key: json['key'],
      name: json['name'],
      site: json['site'],
      type: json['type'],
    );
  }
}
