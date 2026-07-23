import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/debug/note_sync_debug.dart';
import 'attachment_nodes.dart';
import 'note_document_codec.dart';

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

class EditorOperationCapture {
  final MutableDocument _document;
  final String Function() _generateOpId;
  final NoteDocumentCodec _codec;
  final void Function(List<OperationRequestData> requests)
  _onOperationsCaptured;

  final Map<String, _BlockMirror> _mirrors = {};
  List<String> _orderedNodeIds = [];
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
    _orderedNodeIds = [];
    for (final node in _document) {
      _orderedNodeIds.add(node.id);
      AttributedText attrText = AttributedText();
      String? bType;
      Map<String, dynamic> meta = {};

      if (node is TextNode) {
        attrText = node.text;
      }
      bType = _codec.blockTypeName(node);
      if (node is TaskNode) {
        meta = Map<String, dynamic>.from(node.metadata)
          ..['isCompleted'] = node.isComplete;
      } else {
        meta = Map<String, dynamic>.from(node.metadata);
      }
      _mirrors[node.id] = _BlockMirror(
        attributedText: attrText,
        blockType: bType,
        metadata: meta,
      );
    }
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

    if (currentNodes.any(
      (node) => node is TextNode && _hasComposingAttribution(node.text),
    )) {
      NoteSyncDebug.log('capture.deferred_composing');
      return;
    }

    // 1. Deleted blocks
    final deletedIds = _orderedNodeIds
        .where((id) => !currentIds.contains(id))
        .toList();
    for (final delId in deletedIds) {
      requests.add(
        OperationRequestData(
          operationId: _generateOpId(),
          kind: 'delete_block',
          blockId: delId,
          payload: {'blockId': delId},
        ),
      );
      _mirrors.remove(delId);
    }

    // 2. Created & Moved blocks
    for (int i = 0; i < currentNodes.length; i++) {
      final node = currentNodes[i];
      final afterBlockId = i == 0 ? null : currentNodes[i - 1].id;

      if (!_mirrors.containsKey(node.id)) {
        // Created block
        final blockJson = _codec.encodeNode(node);
        requests.add(
          OperationRequestData(
            operationId: _generateOpId(),
            kind: 'create_block',
            blockId: node.id,
            payload: {
              'id': node.id,
              'type': blockJson['type'],
              'delta': blockJson['delta'],
              'metadata': blockJson['metadata'],
              'afterBlockId': afterBlockId,
            },
          ),
        );
      } else {
        // Moved block
        final prevIndexInOld = _orderedNodeIds.indexOf(node.id);
        final expectedAfterId = i == 0 ? null : currentNodes[i - 1].id;
        final actualOldAfterId = prevIndexInOld <= 0
            ? null
            : _orderedNodeIds[prevIndexInOld - 1];

        if (prevIndexInOld != -1 && expectedAfterId != actualOldAfterId) {
          requests.add(
            OperationRequestData(
              operationId: _generateOpId(),
              kind: 'move_block',
              blockId: node.id,
              payload: {'blockId': node.id, 'afterBlockId': expectedAfterId},
            ),
          );
        }
      }
    }

    // 3. Text & Type & Metadata changes
    for (final node in currentNodes) {
      final mirror = _mirrors[node.id];
      if (mirror == null) continue;

      AttributedText currentAttrText = AttributedText();
      String? currentBType;
      Map<String, dynamic> currentMeta = {};

      if (node is TextNode) {
        currentAttrText = node.text;
      }
      currentBType = _codec.blockTypeName(node);
      if (node is TaskNode) {
        currentMeta = Map<String, dynamic>.from(node.metadata)
          ..['isCompleted'] = node.isComplete;
      } else {
        currentMeta = Map<String, dynamic>.from(node.metadata);
      }

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
              kind: 'text_delta',
              blockId: node.id,
              payload: {'ops': deltaOps},
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
            kind: 'set_block_type',
            blockId: node.id,
            payload: {'type': currentBType},
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
                kind: 'complete_task_occurrence',
                blockId: node.id,
                payload: {
                  'taskId': node.id,
                  'scheduledAt': entry.key,
                  'completedAt': entry.value,
                },
              ),
            );
          }
        }

        for (final key in oldCompletions.keys) {
          if (!curCompletions.containsKey(key)) {
            requests.add(
              OperationRequestData(
                operationId: _generateOpId(),
                kind: 'complete_task_occurrence',
                blockId: node.id,
                payload: {
                  'taskId': node.id,
                  'scheduledAt': key,
                  'completedAt': null,
                },
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
              kind: 'set_block_metadata',
              blockId: node.id,
              payload: {'metadata': otherCurMeta},
            ),
          );
        }

        mirror.metadata = currentMeta;
      }
    }

    // A created node must enter the mirror before the next keystroke.
    // Otherwise each text change is incorrectly captured as another create_block.
    buildMirror();

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
      final attrId = marker.attribution.id;
      if (attrId == 'composing') continue;
      if (marker.markerType == SpanMarkerType.start) {
        if (marker.offset <= offset) {
          active.add(attrId);
        }
      } else if (marker.markerType == SpanMarkerType.end) {
        if (marker.offset <= offset) {
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
        diff[a] = false;
      }
    }
    return diff;
  }
}
