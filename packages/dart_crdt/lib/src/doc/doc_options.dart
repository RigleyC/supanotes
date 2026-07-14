part of 'doc.dart';

/// Predicate used to decide whether a value may be garbage-collected.
typedef GcFilter = bool Function(Object value);

/// Immutable constructor options for a [Doc].
final class DocOptions {
  /// Creates document options.
  const DocOptions({
    this.gc = true,
    this.gcFilter,
    this.guid,
    this.collectionId,
    this.meta,
    this.autoLoad = false,
    this.shouldLoad = false,
    this.isSuggestionDocument = false,
    this.clientId,
  });

  /// Whether deleted content may be garbage-collected.
  final bool gc;

  /// Optional application-level garbage-collection filter.
  final GcFilter? gcFilter;

  /// Stable document id.
  final String? guid;

  /// Optional collection id for grouping related documents.
  final String? collectionId;

  /// Application metadata associated with this document.
  final AnyValue? meta;

  /// Whether providers should automatically request document loading.
  final bool autoLoad;

  /// Whether this document has been requested for loading.
  final bool shouldLoad;

  /// Whether this document is used for suggestion or preview state.
  final bool isSuggestionDocument;

  /// Optional deterministic client id, primarily for tests and replay.
  final ClientId? clientId;
}
