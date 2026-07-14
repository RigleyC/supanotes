part of 'diff_snapshot_attribution.dart';

/// Event emitted when attribution ranges change.
final class AttributionChangeEvent {
  /// Creates an attribution change event.
  AttributionChangeEvent({
    required this.changed,
    this.origin,
    required this.local,
  });

  /// Changed content ids.
  final ContentIds changed;

  /// Transaction origin that caused the change.
  final Object? origin;

  /// Whether the source transaction was local.
  final bool local;
}
