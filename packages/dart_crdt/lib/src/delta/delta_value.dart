part of 'delta_operation.dart';

/// Immutable completed delta value.
final class Delta {
  /// Creates an immutable delta from [operations].
  Delta([Iterable<DeltaOperation> operations = const <DeltaOperation>[]])
      : operations = List<DeltaOperation>.unmodifiable(operations);

  /// Operations in application order.
  final List<DeltaOperation> operations;

  /// Operations that affect sequence/text content.
  List<DeltaOperation> get contentOperations {
    return List<DeltaOperation>.unmodifiable(
      operations.where((operation) => !operation.isAttributeOperation),
    );
  }

  /// Operations that affect type-level attributes.
  List<DeltaOperation> get attributeOperations {
    return List<DeltaOperation>.unmodifiable(
      operations.where((operation) => operation.isAttributeOperation),
    );
  }

  /// Total visible content length affected by content operations.
  int get length {
    var result = 0;
    for (final operation in contentOperations) {
      result += operation.length;
    }
    return result;
  }

  /// Whether this delta contains no operations.
  bool get isEmpty => operations.isEmpty;

  /// Whether this delta contains at least one operation.
  bool get isNotEmpty => operations.isNotEmpty;

  /// Creates a new mutable builder seeded with this delta's operations.
  DeltaBuilder toBuilder() => DeltaBuilder(operations);

  /// Converts this delta to a stable JSON-compatible map.
  Map<String, Object?> toJson() => {
        'ops': _operationsToJson(operations),
      };

  /// Stable debug representation used in tests and diagnostics.
  String toDebugString() => toJson().toString();

  @override
  bool operator ==(Object other) {
    return other is Delta && _listEquals(operations, other.operations);
  }

  @override
  int get hashCode => _listHash(operations);

  @override
  String toString() => toDebugString();
}
