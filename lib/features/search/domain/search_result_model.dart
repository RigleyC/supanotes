library;

import 'package:flutter/foundation.dart';

@immutable
class SearchResultModel {
  const SearchResultModel({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.score,
  });

  final String id;
  final String title;
  final String excerpt;
  final double score;

  factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      id: (json['ID'] ?? '') as String,
      title: (json['Title'] ?? '') as String,
      excerpt: (json['Excerpt'] ?? '') as String,
      score: _readScore(json['Score']),
    );
  }

  static double _readScore(Object? raw) {
    if (raw is num) return raw.toDouble();
    return 0.0;
  }
}
