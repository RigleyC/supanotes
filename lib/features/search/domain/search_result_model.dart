/// Domain model for a single search hit returned by the backend.
///
/// The backend (`POST /api/v1/search`, see
/// `backend/internal/search/service.go`) returns a JSON array whose
/// elements correspond to Go's `search.SearchResult` struct. That struct
/// declares **no JSON tags**, so the field names are kept in PascalCase
/// by Go's default `encoding/json` behaviour:
///
/// ```json
/// {
///   "ID":        "uuid-string",
///   "Title":     "...",
///   "Content":   "...",
///   "Excerpt":   "...",
///   "UpdatedAt": "RFC3339",
///   "ContextID": "uuid-or-null",
///   "Favorite":  false,
///   "Archived":  false,
///   "Score":     0.42
/// }
/// ```
///
/// Only the subset the UI needs is materialised here: [id], [title],
/// [excerpt] and [score]. The [mode] does **not** come from the wire —
/// it is the mode the caller asked for, propagated by the repository so
/// each result row can carry its provenance badge.
library;

import 'package:flutter/foundation.dart';

/// Search strategy requested from the backend.
///
/// Wire values (string sent inside the `mode` request field) follow the
/// Go switch in `search.Service.Search`:
///
///   * `fts`      — full-text search (Postgres `tsvector`).
///   * `semantic` — vector search over note embeddings.
///   * `hybrid`   — RRF fusion of FTS + semantic (default).
enum SearchMode {
  fts('fts'),
  semantic('semantic'),
  hybrid('hybrid');

  const SearchMode(this.wireValue);

  /// The string that goes on the wire in the `mode` request field.
  final String wireValue;
}

@immutable
class SearchResultModel {
  const SearchResultModel({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.score,
    required this.mode,
  });

  /// Note id (the value of the Go `ID` field, serialised as a UUID
  /// string by `pgtype.UUID.MarshalJSON`).
  final String id;

  /// Note title. May be empty when the underlying row has no title.
  final String title;

  /// Short snippet (server-side excerpt or FTS headline).
  final String excerpt;

  /// Relevance score in `[0, 1]` (RRF) or raw FTS rank, depending on
  /// the mode. Rendered as a sutile secondary label, not as a primary
  /// signal.
  final double score;

  /// The mode that produced this hit. **Not** part of the JSON payload
  /// — propagated by the repository from the request so the UI can
  /// badge each row.
  final SearchMode mode;

  /// Builds a [SearchResultModel] from one element of the JSON array.
  ///
  /// The [mode] argument is the value the caller requested — the
  /// backend does not echo it back, so the repository injects it here.
  factory SearchResultModel.fromJson(
    Map<String, dynamic> json, {
    required SearchMode mode,
  }) {
    return SearchResultModel(
      id: (json['ID'] ?? '') as String,
      title: (json['Title'] ?? '') as String,
      excerpt: (json['Excerpt'] ?? '') as String,
      score: _readScore(json['Score']),
      mode: mode,
    );
  }

  /// `Score` is a Go `float64`; Dio decodes JSON numbers as either
  /// [int] or [double] depending on whether the wire value had a
  /// decimal point. Coerce both to [double] (and gracefully handle a
  /// missing / non-numeric value).
  static double _readScore(Object? raw) {
    if (raw is num) return raw.toDouble();
    return 0.0;
  }
}
