/// A Dart CRDT package for local-first collaborative data structures.
///
/// Start with `Doc` and a root `SharedType`. Root types can behave as maps,
/// sequences, rich text, or XML-like trees depending on their `SharedTypeKind`.
///
/// ```dart
/// import 'package:dart_crdt/dart_crdt.dart';
///
/// final doc = Doc();
/// final text = doc.getText('body');
///
/// doc.transact((transaction) {
///   text.insertText(0, 'Hello');
/// }, origin: 'editor');
///
/// assert(text.toPlainText() == 'Hello');
/// ```
///
/// Documents exchange binary updates with `encodeStateAsUpdate` and
/// `applyUpdate`. State vectors let a peer request only missing state.
///
/// ```dart
/// final left = Doc();
/// left.getText('body').insertText(0, 'sync');
///
/// final right = Doc();
/// applyUpdate(right, encodeStateAsUpdate(left));
///
/// assert(right.getText('body').toPlainText() == 'sync');
/// ```
///
/// Use `UndoManager` for scoped undo/redo and `RelativePosition` helpers for
/// cursor positions that survive nearby edits.
///
/// ```dart
/// final doc = Doc();
/// final body = doc.getText('body');
/// final undo = UndoManager(body);
/// body.insertText(0, 'draft');
/// undo.undo();
///
/// final cursor = createRelativePositionFromTypeIndex(body, 0);
/// final absolute = createAbsolutePositionFromRelativePosition(cursor, doc);
/// assert(absolute?.index == 0);
/// undo.destroy();
/// ```
///
/// Advanced APIs such as `AbstractStruct`, `Id`, `ContentIds`, `IdSet`, and
/// `StateVector` are exported for binary compatibility tooling, fixture
/// generation, and low-level diagnostics. Prefer `Doc`, `SharedType`,
/// `encodeStateAsUpdate`, `applyUpdate`, `Snapshot`, `RelativePosition`, and
/// `UndoManager` for application code unless you are implementing sync,
/// storage, or interoperability infrastructure.
library;

export 'src/attribution/attribution_manager.dart';
export 'src/attribution/diff_snapshot_attribution.dart';
export 'src/awareness/awareness.dart';
export 'src/binary/any_value.dart';
export 'src/content/content.dart';
export 'src/delta/delta_operation.dart';
export 'src/doc/doc.dart';
export 'src/events/event_handler.dart';
export 'src/metadata/content_attribute.dart';
export 'src/metadata/content_ids.dart';
export 'src/metadata/content_map.dart';
export 'src/metadata/id_map.dart';
export 'src/metadata/id_range.dart';
export 'src/metadata/id_set.dart';
export 'src/package_info.dart';
export 'src/relative_position/relative_position.dart';
export 'src/snapshot/snapshot.dart';
export 'src/structs/abstract_struct.dart';
export 'src/structs/id.dart';
export 'src/sync/apply_update.dart';
export 'src/sync/document_update_helpers.dart';
export 'src/sync/state_update.dart';
export 'src/sync/state_vector.dart';
export 'src/sync/update_algebra.dart';
export 'src/sync/update_content_ids.dart';
export 'src/sync/update_format.dart';
export 'src/sync/update_inspection.dart';
export 'src/sync/update_obfuscation.dart';
export 'src/undo/undo_manager.dart';
