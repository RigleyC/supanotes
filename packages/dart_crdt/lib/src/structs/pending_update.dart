/// Pending update metadata for causally incomplete sync input.
library;

import 'dart:typed_data';

import 'id.dart';

/// Struct update bytes that could not yet be applied.
final class PendingStructs {
  /// Creates pending struct metadata.
  PendingStructs({
    required Map<ClientId, Clock> missing,
    required List<int> update,
    this.version = 1,
  })  : missing = Map.unmodifiable(missing),
        update = Uint8List.fromList(update).asUnmodifiableView();

  /// Missing client clocks required before [update] can be retried.
  final Map<ClientId, Clock> missing;

  /// Raw update bytes to retry after dependencies arrive.
  final Uint8List update;

  /// Update format version for [update].
  final int version;

  /// Whether there are no missing dependencies and no pending bytes.
  bool get isEmpty => missing.isEmpty && update.isEmpty;
}
