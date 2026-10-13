class Review {
  final String author;
  final String content;

  Review({required this.author, required this.content});

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      author: json['author'] ?? 'Unknown',
      content: json['content'] ?? '',
    );
  }
}
