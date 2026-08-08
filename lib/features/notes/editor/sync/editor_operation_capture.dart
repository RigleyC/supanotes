import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_contract.dart';

class OperationRequestData {
  final String operationId;
  final String kind;
  final String? blockId;
  final Map<String, dynamic> payload;

  OperationRequestData({
    required this.operationId,
    required this.kind,
    this.blockId,
    required this.payload,
  });
}

class _BlockMirror {
  AttributedText attributedText;
  String? blockType;
  Map<String, dynamic> metadata;

  _BlockMirror({
    required this.attributedText,
    this.blockType,
    required this.metadata,
  });
}

class _DocumentChangeSummary {
  final Set<String> changedNodeIds;
  final bool hasStructuralChange;

  const _DocumentChangeSummary({
    required this.changedNodeIds,
    required this.hasStructuralChange,
  });
}

class EditorOperationCapture {
  final MutableDocument _document;
  final String Function() _generateOpId;
  final NoteDocumentCodec _codec;
  final void Function(List<OperationRequestData> requests)
  _onOperationsCaptured;

  final Map<String, _BlockMirror> _mirrors = {};
  final Set<String> _deferredChangedNodeIds = {};
  List<String> _orderedNodeIds = [];
  bool _hasDeferredStructuralChange = false;
  bool _suppress = false;
  bool _listening = false;

  EditorOperationCapture({
    required MutableDocument document,
    required String Function() generateOpId,
    required NoteDocumentCodec codec,
    required void Function(List<OperationRequestData> requests)
    onOperationsCaptured,
  }) : _document = document,
       _generateOpId = generateOpId,
       _codec = codec,
       _onOperationsCaptured = onOperationsCaptured;

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
    _mirrors.clear();
    _deferredChangedNodeIds.clear();
    _hasDeferredStructuralChange = false;
    _orderedNodeIds = _document.map((node) => node.id).toList();
    for (final node in _document) {
      _mirrors[node.id] = _mirrorForNode(node);
    }
  }

  _BlockMirror _mirrorForNode(DocumentNode node) {
    final metadata = Map<String, dynamic>.from(node.metadata);
    if (node is TaskNode) {
      metadata['isCompleted'] = node.isComplete;
    }

    return _BlockMirror(
      attributedText: node is TextNode ? node.text : AttributedText(),
      blockType: _codec.blockTypeName(node),
      metadata: metadata,
    );
  }

  _DocumentChangeSummary _summarizeChangeLog(DocumentChangeLog changeLog) {
    final changedNodeIds = <String>{};
    var hasStructuralChange = false;

    for (final change in changeLog.changes) {
      if (change is NodeDocumentChange) {
        changedNodeIds.add(change.nodeId);
      }
      if (change is NodeInsertedEvent ||
          change is NodeRemovedEvent ||
          change is NodeMovedEvent) {
        hasStructuralChange = true;
      }
    }

    return _DocumentChangeSummary(
      changedNodeIds: changedNodeIds,
      hasStructuralChange: hasStructuralChange,
    );
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    if (_suppress) {
      NoteSyncDebug.log(
        'capture.suppressed',
        fields: {'nodeCount': _document.nodeCount},
      );
      return;
    }

    final requests = <OperationRequestData>[];
    final currentNodes = _document.toList();
    final currentIds = currentNodes.map((n) => n.id).toList();
    final currentIdSet = currentIds.toSet();
    final changeSummary = _summarizeChangeLog(changeLog);
    final changedNodeIds = {
      ..._deferredChangedNodeIds,
      ...changeSummary.changedNodeIds,
    };
    final structuralChange =
        _hasDeferredStructuralChange || changeSummary.hasStructuralChange;
    final inspectAllNodes = structuralChange || changedNodeIds.isEmpty;
    final nodesToInspect = inspectAllNodes
        ? currentNodes
        : currentNodes.where((node) => changedNodeIds.contains(node.id));

    if (nodesToInspect.any(
      (node) => node is TextNode && _hasComposingAttribution(node.text),
    )) {
      _deferredChangedNodeIds
        ..clear()
        ..addAll(changedNodeIds);
      _hasDeferredStructuralChange = structuralChange;
      NoteSyncDebug.log('capture.deferred_composing');
      return;
    }
    _deferredChangedNodeIds.clear();
    _hasDeferredStructuralChange = false;

    // 1. Deleted blocks
    final deletedIds = _orderedNodeIds
        .where((id) => !currentIdSet.contains(id))
        .toList();
    for (final delId in deletedIds) {
      requests.add(
        OperationRequestData(
          operationId: _generateOpId(),
          kind: NoteOperationKind.deleteBlock.wireName,
          blockId: delId,
          payload: NoteOperationPayloads.deleteBlock(delId),
        ),
      );
      _mirrors.remove(delId);
    }

    // 2. Created & Moved blocks
    final oldIndexById = <String, int>{
      for (var i = 0; i < _orderedNodeIds.length; i++) _orderedNodeIds[i]: i,
    };
    for (int i = 0; i < currentNodes.length; i++) {
      final node = currentNodes[i];
      final afterBlockId = i == 0 ? null : currentNodes[i - 1].id;

      if (!_mirrors.containsKey(node.id)) {
        // Created block
        final blockJson = _codec.encodeNode(node);
        requests.add(
          OperationRequestData(
            operationId: _generateOpId(),
            kind: NoteOperationKind.createBlock.wireName,
            blockId: node.id,
            payload: NoteOperationPayloads.createBlock(
              block: blockJson,
              afterBlockId: afterBlockId,
            ),
          ),
        );
        _mirrors[node.id] = _mirrorForNode(node);
      } else if (structuralChange) {
        // Moved block
        final prevIndexInOld = oldIndexById[node.id];
        final expectedAfterId = i == 0 ? null : currentNodes[i - 1].id;
        final actualOldAfterId = prevIndexInOld == null || prevIndexInOld <= 0
            ? null
            : _orderedNodeIds[prevIndexInOld - 1];

        if (prevIndexInOld != null && expectedAfterId != actualOldAfterId) {
          requests.add(
            OperationRequestData(
              operationId: _generateOpId(),
              kind: NoteOperationKind.moveBlock.wireName,
              blockId: node.id,
              payload: NoteOperationPayloads.moveBlock(
                blockId: node.id,
                afterBlockId: expectedAfterId,
              ),
            ),
          );
        }
      }
    }

    // 3. Text & Type & Metadata changes
    for (final node in nodesToInspect) {
      final mirror = _mirrors[node.id];
      if (mirror == null) continue;

      final currentMirror = _mirrorForNode(node);
      final currentAttrText = currentMirror.attributedText;
      final currentBType = currentMirror.blockType;
      final currentMeta = currentMirror.metadata;

      // Check attributed text change
      if (currentAttrText != mirror.attributedText) {
        final deltaOps = _computeAttributedTextDelta(
          mirror.attributedText,
          currentAttrText,
        );
        if (deltaOps.isNotEmpty) {
          requests.add(
            OperationRequestData(
              operationId: _generateOpId(),
              kind: NoteOperationKind.textDelta.wireName,
              blockId: node.id,
              payload: NoteOperationPayloads.textDelta(ops: deltaOps),
            ),
          );
        }
        mirror.attributedText = currentAttrText;
      }

      // Check type change
      if (currentBType != mirror.blockType && currentBType != null) {
        requests.add(
          OperationRequestData(
            operationId: _generateOpId(),
            kind: NoteOperationKind.setBlockType.wireName,
            blockId: node.id,
            payload: NoteOperationPayloads.setBlockType(currentBType),
          ),
        );
        mirror.blockType = currentBType;
      }

      // Check metadata change
      if (!mapEquals(currentMeta, mirror.metadata)) {
        final curCompletions = Map<String, dynamic>.from(
          currentMeta['completions'] as Map? ?? {},
        );
        final oldCompletions = Map<String, dynamic>.from(
          mirror.metadata['completions'] as Map? ?? {},
        );

        for (final entry in curCompletions.entries) {
          if (oldCompletions[entry.key] != entry.value) {
            requests.add(
              OperationRequestData(
                operationId: _generateOpId(),
                kind: NoteOperationKind.completeTaskOccurrence.wireName,
                blockId: node.id,
                payload: NoteOperationPayloads.completeTaskOccurrence(
                  taskId: node.id,
                  scheduledAt: entry.key,
                  completedAt: entry.value as String?,
                ),
              ),
            );
          }
        }

        for (final key in oldCompletions.keys) {
          if (!curCompletions.containsKey(key)) {
            requests.add(
              OperationRequestData(
                operationId: _generateOpId(),
                kind: NoteOperationKind.completeTaskOccurrence.wireName,
                blockId: node.id,
                payload: NoteOperationPayloads.completeTaskOccurrence(
                  taskId: node.id,
                  scheduledAt: key,
                  completedAt: null,
                ),
              ),
            );
          }
        }

        final otherCurMeta = Map<String, dynamic>.from(currentMeta)
          ..remove('completions');
        final otherOldMeta = Map<String, dynamic>.from(mirror.metadata)
          ..remove('completions');
        if (!mapEquals(otherCurMeta, otherOldMeta)) {
          for (final key in otherOldMeta.keys) {
            if (!otherCurMeta.containsKey(key)) {
              otherCurMeta[key] = null;
            }
          }
          requests.add(
            OperationRequestData(
              operationId: _generateOpId(),
              kind: NoteOperationKind.setBlockMetadata.wireName,
              blockId: node.id,
              payload: NoteOperationPayloads.setBlockMetadata(otherCurMeta),
            ),
          );
        }

        mirror.metadata = currentMeta;
      }
    }

    _orderedNodeIds = currentIds;

    if (requests.isNotEmpty) {
      NoteSyncDebug.log(
        'capture.operations',
        fields: {
          'nodeCount': currentNodes.length,
          'operations': requests
              .map(
                (request) =>
                    '${request.kind}:${request.blockId}:${NoteSyncDebug.payloadSummary(request.payload)}',
              )
              .join('|'),
        },
      );
      _onOperationsCaptured(requests);
    }
  }

  List<Map<String, dynamic>> _computeAttributedTextDelta(
    AttributedText oldText,
    AttributedText newText,
  ) {
    final oldStr = oldText.toPlainText();
    final newStr = newText.toPlainText();

    // 1. Identical plain text: compare attributions per character
    if (oldStr == newStr) {
      final ops = <Map<String, dynamic>>[];
      int pos = 0;
      while (pos < oldStr.length) {
        final oldAttrs = _getAttributionsAt(oldText, pos);
        final newAttrs = _getAttributionsAt(newText, pos);
        final attrDiff = _diffAttributes(oldAttrs, newAttrs);

        int runEnd = pos + 1;
        while (runEnd < oldStr.length) {
          final nextOld = _getAttributionsAt(oldText, runEnd);
          final nextNew = _getAttributionsAt(newText, runEnd);
          final nextDiff = _diffAttributes(nextOld, nextNew);
          if (!mapEquals(attrDiff, nextDiff)) break;
          runEnd++;
        }

        final retainLength = runEnd - pos;
        final op = <String, dynamic>{'retain': retainLength};
        if (attrDiff.isNotEmpty) {
          op['attributes'] = attrDiff;
        }
        ops.add(op);
        pos = runEnd;
      }
      return ops;
    }

    // 2. Text changed: compute prefix, delete, insert with attributes, suffix
    int prefixLen = 0;
    while (prefixLen < oldStr.length &&
        prefixLen < newStr.length &&
        oldStr[prefixLen] == newStr[prefixLen]) {
      prefixLen++;
    }

    int suffixLen = 0;
    while (suffixLen < (oldStr.length - prefixLen) &&
        suffixLen < (newStr.length - prefixLen) &&
        oldStr[oldStr.length - 1 - suffixLen] ==
            newStr[newStr.length - 1 - suffixLen]) {
      suffixLen++;
    }

    final deletedCount = oldStr.length - prefixLen - suffixLen;
    final insertedStr = newStr.substring(prefixLen, newStr.length - suffixLen);

    final ops = <Map<String, dynamic>>[];

    // A text edit must not also rewrite attributes in unchanged text. IMEs
    // can transiently change those attributes while they compose input.
    if (prefixLen > 0) {
      ops.add({'retain': prefixLen});
    }

    // Delete
    if (deletedCount > 0) {
      ops.add({'delete': deletedCount});
    }

    // Insert
    if (insertedStr.isNotEmpty) {
      final insertSub = newText.copyText(
        prefixLen,
        prefixLen + insertedStr.length,
      );
      final insertOps = _codec.encodeAttributedTextToDelta(insertSub);
      final insertionWasBold =
          prefixLen > 0 &&
          _getAttributionsAt(oldText, prefixLen - 1).contains('bold');
      if (!insertionWasBold) {
        for (final op in insertOps) {
          final attributes = op['attributes'];
          if (attributes is Map && attributes.containsKey('bold')) {
            final cleaned = Map<String, dynamic>.from(attributes)
              ..remove('bold');
            if (cleaned.isEmpty) {
              op.remove('attributes');
            } else {
              op['attributes'] = cleaned;
            }
          }
        }
      }
      ops.addAll(insertOps);
    }

    return ops;
  }

  Set<String> _getAttributionsAt(AttributedText text, int offset) {
    if (text.toPlainText().isEmpty) return const {};
    final active = <String>{};
    for (final marker in text.spans.markers) {
      final attrId = NoteDocumentCodec.attributionToName(marker.attribution);
      if (attrId == 'composing') continue;
      if (marker.markerType == SpanMarkerType.start) {
        if (marker.offset <= offset) {
          active.add(attrId);
        }
      } else if (marker.markerType == SpanMarkerType.end) {
        if (marker.offset < offset) {
          active.remove(attrId);
        }
      }
    }
    return active;
  }

  bool _hasComposingAttribution(AttributedText text) {
    return text.spans.markers.any(
      (marker) =>
          marker.markerType == SpanMarkerType.start &&
          marker.attribution.id == 'composing',
    );
  }

  Map<String, dynamic> _diffAttributes(
    Set<String> oldAttrs,
    Set<String> newAttrs,
  ) {
    final diff = <String, dynamic>{};
    for (final a in newAttrs) {
      if (!oldAttrs.contains(a)) {
        diff[a] = true;
      }
    }
    for (final a in oldAttrs) {
      if (!newAttrs.contains(a)) {
        diff[a] = null;
      }
    }
    return diff;
  }
}
