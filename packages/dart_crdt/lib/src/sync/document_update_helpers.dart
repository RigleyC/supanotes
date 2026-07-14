/// Convenience helpers for creating documents from updates.
library;

import '../doc/doc.dart';
import 'apply_update.dart';
import 'state_update.dart';

/// Creates a document from a V1 [update].
///
/// Example:
/// ```dart
/// final doc = createDocFromUpdate(updateBytes);
/// ```
Doc createDocFromUpdate(
  List<int> update, {
  DocOptions? options,
  Object? origin,
}) {
  final doc = options == null ? Doc() : Doc.withOptions(options);
  applyUpdate(doc, update, origin: origin);
  return doc;
}

/// Creates a document from a V2 [update].
///
/// Example:
/// ```dart
/// final doc = createDocFromUpdateV2(updateBytes);
/// ```
Doc createDocFromUpdateV2(
  List<int> update, {
  DocOptions? options,
  Object? origin,
}) {
  final doc = options == null ? Doc() : Doc.withOptions(options);
  applyUpdateV2(doc, update, origin: origin);
  return doc;
}

/// Creates an independent clone of [source].
///
/// Example:
/// ```dart
/// final cloned = cloneDoc(sourceDoc);
/// ```
Doc cloneDoc(
  Doc source, {
  DocOptions? options,
  Object? origin,
}) {
  return createDocFromUpdate(
    encodeStateAsUpdate(source),
    options: options,
    origin: origin,
  );
}
