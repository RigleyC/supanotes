import 'package:flutter/foundation.dart';
import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_editor_operation_builder.dart';
import 'package:super_editor/super_editor.dart';

class OperationRequestData {
  OperationRequestData({
    required this.operationId,
    required this.kind,
    required this.payload,
    this.blockId,
  });

  final String operationId;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;
}

/// Listens to editor changes and adapts pure document operations to the
/// sync-layer request type.
///
/// Mirroring and IME deferral belong here because they are lifecycle concerns.
/// The operation diff itself is delegated to [NoteEditorOperationBuilder],
/// which is deterministic and can be tested without a document listener.
final class EditorOperationCapture {
  EditorOperationCapture({
    required MutableDocument document,
    required String Function() generateOpId,
    required NoteDocumentCodec codec,
    required void Function(List<OperationRequestData> requests)
    onOperationsCaptured,
  }) : _document = document,
       _generateOpId = generateOpId,
       _builder = NoteEditorOperationBuilder(codec: codec),
       _onOperationsCaptured = onOperationsCaptured;

  final MutableDocument _document;
  final String Function() _generateOpId;
  final NoteEditorOperationBuilder _builder;
  final void Function(List<OperationRequestData> requests)
  _onOperationsCaptured;

  late NoteEditorDocumentSnapshot _mirror;
  bool _suppress = false;
  bool _listening = false;

  bool get isListening => _listening;

  void setSuppress(bool suppress) {
    _suppress = suppress;
  }

  void start() {
    if (_listening) return;
    buildMirror();
    _document.addListener(_onDocumentChanged);
    _listening = true;
  }

  void stop() {
    if (!_listening) return;
    _document.removeListener(_onDocumentChanged);
    _listening = false;
  }

  void buildMirror() {
    _mirror = NoteEditorDocumentSnapshot.fromDocument(
      _document,
      _builder.codec,
    );
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    if (_suppress) {
      if (kDebugMode) {
        NoteSyncDebug.log(
          'capture.suppressed',
          fields: {'nodeCount': _document.nodeCount},
        );
      }
      return;
    }

    final current = _snapshotAfterChange(changeLog);

    final operations = _builder.build(before: _mirror, after: current);
    _mirror = current;
    if (operations.isEmpty) return;

    final requests = operations
        .map(
          (operation) => OperationRequestData(
            operationId: _generateOpId(),
            kind: operation.kind.wireName,
            blockId: operation.blockId,
            payload: operation.payload,
          ),
        )
        .toList(growable: false);

    if (kDebugMode) {
      NoteSyncDebug.log(
        'capture.operations',
        fields: {
          'nodeCount': current.blocks.length,
          'operations': requests
              .map(
                (request) =>
                    '${request.kind}:${request.blockId}:${NoteSyncDebug.payloadSummary(request.payload)}',
              )
              .join('|'),
        },
      );
    }
    _onOperationsCaptured(requests);
  }

  /// Builds the post-change snapshot from the change log.
  ///
  /// Typing only produces [NodeChangeEvent] entries, so re-reading the changed
  /// nodes keeps the cost proportional to the edit instead of re-encoding the
  /// whole document on every keystroke. Insert, move and remove events change
  /// the block order, which the diff needs in full.
  NoteEditorDocumentSnapshot _snapshotAfterChange(
    DocumentChangeLog changeLog,
  ) {
    final changedNodeIds = <String>{};
    var requiresFullRebuild = changeLog.changes.isEmpty;
    for (final change in changeLog.changes) {
      if (change is! NodeChangeEvent) {
        requiresFullRebuild = true;
        break;
      }
      changedNodeIds.add(change.nodeId);
    }

    if (!requiresFullRebuild) {
      final updated = _mirror.withUpdatedBlocks(
        document: _document,
        codec: _builder.codec,
        changedNodeIds: changedNodeIds,
      );
      if (updated != null) return updated;
    }

    return NoteEditorDocumentSnapshot.fromDocument(
      _document,
      _builder.codec,
    );
  }
}
