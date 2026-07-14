part of 'delta_operation.dart';

/// Mutable helper for assembling immutable [Delta] values.
final class DeltaBuilder {
  /// Creates a builder seeded with [operations].
  DeltaBuilder([Iterable<DeltaOperation> operations = const <DeltaOperation>[]])
      : _operations = List<DeltaOperation>.of(operations);

  final List<DeltaOperation> _operations;

  /// Current operations snapshot.
  List<DeltaOperation> get operations {
    return List<DeltaOperation>.unmodifiable(_operations);
  }

  /// Whether no operations have been appended.
  bool get isEmpty => _operations.isEmpty;

  /// Whether at least one operation has been appended.
  bool get isNotEmpty => _operations.isNotEmpty;

  /// Appends an arbitrary [operation].
  void append(DeltaOperation operation) {
    _operations.add(operation);
  }

  /// Appends a text insertion.
  void insertText({
    required String text,
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    append(DeltaInsertText(text: text, attributes: attributes));
  }

  /// Appends list-content insertion.
  void insertValues(
    Iterable<AnyValue> values, {
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    append(DeltaInsertListContent(values, attributes: attributes));
  }

  /// Appends list-content insertion from Dart objects.
  void insertObjects(
    Iterable<Object?> values, {
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    append(
      DeltaInsertListContent.fromObjects(values, attributes: attributes),
    );
  }

  /// Appends a retain operation.
  void retain({
    required int length,
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    append(DeltaRetain(length: length, attributes: attributes));
  }

  /// Appends a delete operation.
  void delete(int length) {
    append(DeltaDelete(length));
  }

  /// Appends a nested child modification.
  void modifyChild({
    required Delta delta,
    DeltaAttributes attributes = DeltaAttributes.empty,
  }) {
    append(
      DeltaModifyChild(
        operations: delta.operations,
        attributes: attributes,
      ),
    );
  }

  /// Appends a type-level set-attribute operation.
  void setAttribute({
    required String key,
    required Object? value,
  }) {
    append(DeltaSetAttribute(key: key, value: value));
  }

  /// Appends a type-level delete-attribute operation.
  void deleteAttribute(String key) {
    append(DeltaDeleteAttribute(key));
  }

  /// Appends a type-level modify-attribute operation.
  void modifyAttribute({
    required String key,
    required Delta delta,
  }) {
    append(DeltaModifyAttribute(key: key, operations: delta.operations));
  }

  /// Removes all appended operations.
  void clear() {
    _operations.clear();
  }

  /// Produces an immutable completed delta.
  Delta done() => Delta(_operations);
}
