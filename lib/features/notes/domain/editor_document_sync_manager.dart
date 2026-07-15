import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:super_editor/super_editor.dart';

import 'note_node.dart';
import 'attachment_nodes.dart';

sealed class NodeOperation {}

class InsertOp extends NodeOperation {
  final String id;
  final DocumentNode node;
  final int index;
  InsertOp(this.id, this.node, this.index);
}

class UpdateOp extends NodeOperation {
  final String id;
  final DocumentNode node;
  UpdateOp(this.id, this.node);
}

class MoveOp extends NodeOperation {
  final String id;
  final int from;
  final int to;
  MoveOp(this.id, this.from, this.to);
}

class DeleteOp extends NodeOperation {
  final String id;
  DeleteOp(this.id);
}

/// Coordinates remote-to-local sync and local dirty tracking for a single note.
///
/// Merges the former [NoteSyncCoordinator] (remote→local application) and
/// [NodeSyncManager] (local→remote dirty tracking & serialization) into one
/// class to eliminate delegation indirection.
class EditorDocumentSyncManager {
  EditorDocumentSyncManager({
    required MutableDocument document,
    required Editor editor,
    this.onNodeFlush,
  })  : _document = document,
        _editor = editor {
    _document.addListener(_onDocumentChanged);
  }

  final MutableDocument _document;
  final Editor _editor;
  void Function(List<NodeOperation> ops)? onNodeFlush;

  final List<NodeOperation> _pendingOps = [];
  Timer? _debounceTimer;

  final Set<String> locallyDirtyNodeIds = {};

  int _opSequence = 0;
  final Map<String, int> _dirtyNodeSequences = {};

  Future<void> _writeLock = Future.value();

  void _enqueueDbWrite(FutureOr<void> Function() action) {
    _writeLock = _writeLock.then((_) async {
      try {
        await action();
      } catch (e, stackTrace) {
        dev.log('SQLite write error: $e', name: 'EditorDocumentSyncManager', error: e, stackTrace: stackTrace, level: 1000);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Local document observation
  // ---------------------------------------------------------------------------

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    _opSequence++;
    for (final change in changeLog.changes) {
      if (change is NodeInsertedEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node != null) {
          _pendingOps.add(InsertOp(change.nodeId, node, change.insertionIndex));
          locallyDirtyNodeIds.add(change.nodeId);
          _dirtyNodeSequences[change.nodeId] = _opSequence;
        }
      } else if (change is NodeRemovedEvent) {
        _pendingOps.add(DeleteOp(change.nodeId));
        locallyDirtyNodeIds.add(change.nodeId);
        _dirtyNodeSequences[change.nodeId] = _opSequence;
      } else if (change is NodeMovedEvent) {
        _pendingOps.add(MoveOp(change.nodeId, change.from, change.to));
        locallyDirtyNodeIds.add(change.nodeId);
        _dirtyNodeSequences[change.nodeId] = _opSequence;
      } else if (change is NodeChangeEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node != null) {
          _pendingOps.add(UpdateOp(change.nodeId, node));
          locallyDirtyNodeIds.add(change.nodeId);
          _dirtyNodeSequences[change.nodeId] = _opSequence;
        }
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _enqueueDbWrite(_drainQueue);
    });
  }

  Future<void> _drainQueue() async {
    if (_pendingOps.isEmpty) return;

    final opsToProcess = List<NodeOperation>.from(_pendingOps);
    _pendingOps.clear();
    final snapshotSeq = _opSequence;

    final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
    for (final id in flushedIds) {
      final seq = _dirtyNodeSequences[id];
      if (seq != null && seq <= snapshotSeq) {
        locallyDirtyNodeIds.remove(id);
        _dirtyNodeSequences.remove(id);
      }
    }

    if (opsToProcess.isNotEmpty) {
      onNodeFlush?.call(opsToProcess);
    }
  }

  Future<void> flushNow() {
    _debounceTimer?.cancel();
    if (_pendingOps.isEmpty) return _writeLock;

    final opsToProcess = List<NodeOperation>.from(_pendingOps);
    _pendingOps.clear();
    final snapshotSeq = _opSequence;

    _enqueueDbWrite(() async {
      final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
      for (final id in flushedIds) {
        final seq = _dirtyNodeSequences[id];
        if (seq != null && seq <= snapshotSeq) {
          locallyDirtyNodeIds.remove(id);
          _dirtyNodeSequences.remove(id);
        }
      }
    });

    if (opsToProcess.isNotEmpty) {
      onNodeFlush?.call(opsToProcess);
    }

    return _writeLock;
  }

  static String? _opNodeId(NodeOperation op) => switch (op) {
    InsertOp(:final id) => id,
    UpdateOp(:final id) => id,
    MoveOp(:final id) => id,
    DeleteOp(:final id) => id,
  };

  // ---------------------------------------------------------------------------
  // Remote-change application
  // ---------------------------------------------------------------------------

  void updateNodesIncrementally(List<NoteNode> incomingNodes) {
    _applyRemote(() => _applyIncomingNodes(incomingNodes));
  }

  void syncTaskStates(Map<String, bool> taskCompletionMap) {
    _applyRemote(() => _applyTaskCompletionStates(taskCompletionMap));
  }

  void _applyRemote(void Function() fn) {
    suspendSync();
    try {
      fn();
    } finally {
      resumeSync();
    }
  }

  void _applyIncomingNodes(List<NoteNode> incomingNodes) {
    if (incomingNodes.isEmpty) {
      return;
    }

    final dirtyIds = locallyDirtyNodeIds;
    final requests = <EditRequest>[];
    final incomingIds = incomingNodes.map((n) => n.id).toSet();

    for (int i = 0; i < incomingNodes.length; i++) {
      final incoming = incomingNodes[i];
      final existingNode = _document.getNodeById(incoming.id);

      if (existingNode == null) {
        final newNode = createNodeFromSchema(incoming);
        requests.add(InsertNodeAtIndexRequest(nodeIndex: i, newNode: newNode));
      } else {
        if (dirtyIds.contains(incoming.id)) continue;

        if (existingNode is TaskNode && incoming.type == 'task') {
          try {
            final existingData = jsonDecode(nodeData(existingNode)) as Map<String, dynamic>;
            final incomingData = jsonDecode(incoming.data) as Map<String, dynamic>;

            final existingWithoutCompleted = Map.from(existingData)..remove('completed');
            final incomingWithoutCompleted = Map.from(incomingData)..remove('completed');

            if (_isMapEqual(existingWithoutCompleted, incomingWithoutCompleted)) {
              final isDbCompleted = incomingData['completed'] as bool? ?? false;
              if (existingNode.isComplete != isDbCompleted) {
                requests.add(ChangeTaskCompletionRequest(
                  nodeId: incoming.id,
                  isComplete: isDbCompleted,
                ));
              }
              continue;
            }
          } catch (_) {}
        }

        if (_isNodeEquivalent(existingNode, incoming)) continue;
        final newNode = createNodeFromSchema(incoming);
        requests.add(
          ReplaceNodeRequest(
            existingNodeId: incoming.id,
            newNode: newNode,
          ),
        );
      }
    }

    for (final node in _document.toList()) {
      if (!incomingIds.contains(node.id)) {
        if (dirtyIds.contains(node.id)) continue;
        requests.add(DeleteNodeRequest(nodeId: node.id));
      }
    }

    if (requests.isNotEmpty) {
      _executeAndPreserveSelection(requests);
    }
  }

  void _applyTaskCompletionStates(Map<String, bool> taskCompletionMap) {
    final requests = <EditRequest>[];
    for (final node in _document) {
      if (node is TaskNode) {
        final isDbCompleted = taskCompletionMap[node.id] ?? false;
        if (node.isComplete != isDbCompleted) {
          requests.add(ChangeTaskCompletionRequest(
            nodeId: node.id,
            isComplete: isDbCompleted,
          ));
        }
      }
    }
    if (requests.isNotEmpty) {
      _executeAndPreserveSelection(requests);
    }
  }

  void _executeAndPreserveSelection(List<EditRequest> requests) {
    if (requests.isEmpty) return;

    final composer = _editor.context.composer;
    final oldSelection = composer.selection;

    _editor.execute(requests);

    if (oldSelection != null) {
      final baseNodeExists = _document.getNodeById(oldSelection.base.nodeId) != null;
      final extentNodeExists = _document.getNodeById(oldSelection.extent.nodeId) != null;
      if (baseNodeExists && extentNodeExists) {
        DocumentSelection finalSelection = oldSelection;
        final baseNode = _document.getNodeById(oldSelection.base.nodeId);
        final extentNode = _document.getNodeById(oldSelection.extent.nodeId);

        DocumentPosition? newBase = oldSelection.base;
        DocumentPosition? newExtent = oldSelection.extent;

        if (baseNode is TextNode && oldSelection.base.nodePosition is TextNodePosition) {
          final maxLen = baseNode.text.toPlainText().length;
          final offset = (oldSelection.base.nodePosition as TextNodePosition).offset;
          if (offset > maxLen) {
            newBase = DocumentPosition(
              nodeId: oldSelection.base.nodeId,
              nodePosition: TextNodePosition(offset: maxLen),
            );
          }
        }
        if (extentNode is TextNode && oldSelection.extent.nodePosition is TextNodePosition) {
          final maxLen = extentNode.text.toPlainText().length;
          final offset = (oldSelection.extent.nodePosition as TextNodePosition).offset;
          if (offset > maxLen) {
            newExtent = DocumentPosition(
              nodeId: oldSelection.extent.nodeId,
              nodePosition: TextNodePosition(offset: maxLen),
            );
          }
        }

        finalSelection = DocumentSelection(base: newBase, extent: newExtent);

        if (finalSelection != composer.selection) {
          _editor.execute([
            ChangeSelectionRequest(
              finalSelection,
              SelectionChangeType.placeCaret,
              SelectionReason.contentChange,
            ),
          ]);
        }
      }
    }
  }

  bool _isNodeEquivalent(DocumentNode existingNode, NoteNode incoming) {
    final existingAttribution = _existingAttribution(existingNode);
    if (existingAttribution != incoming.type) return false;

    if (existingNode is TextNode &&
        incoming.type != 'image' &&
        incoming.type != 'divider') {
      final data = jsonDecode(incoming.data) as Map<String, dynamic>;
      if (existingNode.text.toPlainText() != (data['text'] as String? ?? '')) {
        return false;
      }
    }

    final existingDataStr = nodeData(existingNode);
    try {
      final existingData = jsonDecode(existingDataStr) as Map<String, dynamic>;
      final incomingData = jsonDecode(incoming.data) as Map<String, dynamic>;
      final isEq = _isMapEqual(existingData, incomingData);
      if (!isEq) {
        dev.log(
          '[EditorDocumentSyncManager] NODE NOT EQUIVALENT ID=${incoming.id} TYPE=${incoming.type}\n'
          'Existing: $existingData\n'
          'Incoming: $incomingData',
          name: 'SyncService',
        );
      }
      return isEq;
    } catch (_) {
      return false;
    }
  }

  bool _isMapEqual(Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      final valA = a[key];
      final valB = b[key];
      if (valA is Map && valB is Map) {
        if (!_isMapEqual(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_isListEqual(valA, valB)) return false;
      } else {
        if (valA != valB) return false;
      }
    }
    return true;
  }

  bool _isListEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final valA = a[i];
      final valB = b[i];
      if (valA is Map && valB is Map) {
        if (!_isMapEqual(valA, valB)) return false;
      } else if (valA is List && valB is List) {
        if (!_isListEqual(valA, valB)) return false;
      } else {
        if (valA != valB) return false;
      }
    }
    return true;
  }

  String? _existingAttribution(DocumentNode node) {
    if (node is ParagraphNode) {
      final blockType = node.getMetadataValue('blockType') as Attribution?;
      if (blockType == null) return 'paragraph';
      if (blockType == blockquoteAttribution) return 'blockquote';
      return 'header';
    }
    if (node is TaskNode) return 'task';
    if (node is ListItemNode) return 'list_item';
    if (node is HorizontalRuleNode) return 'divider';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _serializeAttributedText(AttributedText text) {
    final spansList = <Map<String, dynamic>>[];
    for (final span in text.spans.markers) {
      if (span.isStart) {
        String attributionName;
        final attribution = span.attribution;
        if (attribution.id == 'composing') continue;

        if (attribution == boldAttribution) {
          attributionName = 'bold';
        } else if (attribution == italicsAttribution) {
          attributionName = 'italics';
        } else if (attribution == strikethroughAttribution) {
          attributionName = 'strikethrough';
        } else if (attribution == underlineAttribution) {
          attributionName = 'underline';
        } else if (attribution is LinkAttribution) {
          attributionName = 'link:${attribution.plainTextUri.toString()}';
        } else {
          attributionName = attribution.id;
        }

        spansList.add({
          'attribution': attributionName,
          'start': span.offset,
          'end': -1,
        });
      } else {
        String attributionName;
        final attribution = span.attribution;
        if (attribution.id == 'composing') continue;

        if (attribution == boldAttribution) {
          attributionName = 'bold';
        } else if (attribution == italicsAttribution) {
          attributionName = 'italics';
        } else if (attribution == strikethroughAttribution) {
          attributionName = 'strikethrough';
        } else if (attribution == underlineAttribution) {
          attributionName = 'underline';
        } else if (attribution is LinkAttribution) {
          attributionName = 'link:${attribution.plainTextUri.toString()}';
        } else {
          attributionName = attribution.id;
        }

        for (int i = spansList.length - 1; i >= 0; i--) {
          if (spansList[i]['attribution'] == attributionName &&
              spansList[i]['end'] == -1) {
            spansList[i]['end'] = span.offset;
            break;
          }
        }
      }
    }
    return {'text': text.toPlainText(), 'spans': spansList};
  }

  static String nodeData(DocumentNode node) {
    if (node is TaskNode) {
      return jsonEncode({
        ..._serializeAttributedText(node.text),
        'indent': node.indent,
      });
    }
    if (node is ParagraphNode) {
      final blockType = node.metadata['blockType'];
      if (blockType == header1Attribution ||
          blockType == header2Attribution ||
          blockType == header3Attribution ||
          blockType == header4Attribution ||
          blockType == header5Attribution ||
          blockType == header6Attribution) {
        int level = 1;
        if (blockType == header2Attribution) level = 2;
        if (blockType == header3Attribution) level = 3;
        if (blockType == header4Attribution) level = 4;
        if (blockType == header5Attribution) level = 5;
        if (blockType == header6Attribution) level = 6;
        return jsonEncode({
          ..._serializeAttributedText(node.text),
          'level': level,
        });
      }
      if (blockType == blockquoteAttribution) {
        return jsonEncode({..._serializeAttributedText(node.text)});
      }
      return jsonEncode({..._serializeAttributedText(node.text)});
    }
    if (node is ListItemNode) {
      return jsonEncode({
        ..._serializeAttributedText(node.text),
        'type': node.type == ListItemType.ordered ? 'ordered' : 'unordered',
        'indent': node.indent,
      });
    }
    if (node is TextNode) {
      return jsonEncode({..._serializeAttributedText(node.text)});
    }
    if (node is ImageNode) {
      return jsonEncode({'url': node.imageUrl, 'alt': node.altText});
    }
    if (node is HorizontalRuleNode) {
      return '{}';
    }
    if (node is DocumentAttachmentNode) {
      return jsonEncode({'id': node.id});
    }
    if (node is RichLinkNode) {
      return jsonEncode({
        'id': node.id,
        if (node.url != null) 'url': node.url,
        if (node.title != null) 'title': node.title,
        if (node.description != null) 'description': node.description,
        if (node.imageUrl != null) 'image_url': node.imageUrl,
        if (node.domain != null) 'domain': node.domain,
      });
    }
    return '{}';
  }

  static MutableDocument documentFromNodes(List<NoteNode> nodes) {
    final documentNodes = <DocumentNode>[];
    for (final node in nodes) {
      final docNode = _nodeFromData(node);
      if (docNode != null) {
        documentNodes.add(docNode);
      }
    }
    if (documentNodes.isEmpty) {
      return MutableDocument(
        nodes: [
          ParagraphNode(id: Editor.createNodeId(), text: AttributedText()),
        ],
      );
    }
    return MutableDocument(nodes: documentNodes);
  }

  static DocumentNode createNodeFromSchema(NoteNode schema) {
    final type = schema.type;
    final data = jsonDecode(schema.data) as Map<String, dynamic>;
    final text = data['text'] as String? ?? '';
    final spans = data['spans'] as List? ?? [];
    final attributedText = AttributedText(text, deserializeSpans(spans));

    if (type == 'task') {
      return TaskNode(
        id: schema.id,
        text: attributedText,
        isComplete: data['completed'] as bool? ?? false,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'list_item') {
      return ListItemNode(
        id: schema.id,
        itemType: (data['itemType'] as String?) == 'ordered'
            ? ListItemType.ordered
            : ListItemType.unordered,
        text: attributedText,
        indent: data['indent'] as int? ?? 0,
      );
    }
    if (type == 'divider') {
      return HorizontalRuleNode(id: schema.id);
    }
    if (type == 'header') {
      final level = data['level'] as int? ?? 1;
      final blockType = switch (level) {
        1 => header1Attribution,
        2 => header2Attribution,
        3 => header3Attribution,
        4 => header4Attribution,
        5 => header5Attribution,
        _ => header6Attribution,
      };
      return ParagraphNode(
        id: schema.id,
        text: attributedText,
        metadata: {'blockType': blockType},
      );
    }
    if (type == 'image') {
      return ImageNode(
        id: schema.id,
        imageUrl: data['url'] as String? ?? '',
        altText: data['alt'] as String? ?? '',
      );
    }
    return ParagraphNode(id: schema.id, text: attributedText);
  }

  static SpanMarker parseSpan(Map<String, dynamic> spanMap) {
    final name = spanMap['attribution'] as String;
    final Attribution attribution;
    if (name == 'bold') {
      attribution = boldAttribution;
    } else if (name == 'italics') {
      attribution = italicsAttribution;
    } else if (name == 'strikethrough') {
      attribution = strikethroughAttribution;
    } else if (name == 'underline') {
      attribution = underlineAttribution;
    } else if (name.startsWith('link:')) {
      attribution = LinkAttribution.fromUri(Uri.parse(name.substring(5)));
    } else {
      attribution = NamedAttribution(name);
    }
    return SpanMarker(
      attribution: attribution,
      offset: spanMap['start'] as int,
      markerType: SpanMarkerType.start,
    );
  }

  static AttributedSpans deserializeSpans(List spansJson) {
    final list = <SpanMarker>[];
    for (final s in spansJson) {
      final m = s as Map<String, dynamic>;
      final end = m['end'] as int;
      final parsed = parseSpan(m);
      list.add(parsed);
      list.add(
        SpanMarker(
          attribution: parsed.attribution,
          offset: end,
          markerType: SpanMarkerType.end,
        ),
      );
    }
    return AttributedSpans(attributions: list);
  }

  static AttributedText _deserializeAttributedText(Map<String, dynamic> data) {
    final text = data['text'] as String? ?? '';
    final spansData = data['spans'] as List<dynamic>? ?? [];
    final spans = AttributedSpans();

    for (final s in spansData) {
      final spanMap = s as Map<String, dynamic>;
      final attributionName = spanMap['attribution'] as String?;
      final start = spanMap['start'] as int?;
      final end = spanMap['end'] as int?;

      if (attributionName == null || start == null || end == null || end == -1) {
        continue;
      }

      Attribution attribution;
      if (attributionName == 'bold') {
        attribution = boldAttribution;
      } else if (attributionName == 'italics') {
        attribution = italicsAttribution;
      } else if (attributionName == 'strikethrough') {
        attribution = strikethroughAttribution;
      } else if (attributionName == 'underline') {
        attribution = underlineAttribution;
      } else if (attributionName.startsWith('link:')) {
        final urlStr = attributionName.substring(5);
        attribution = LinkAttribution.fromUri(Uri.parse(urlStr));
      } else {
        attribution = NamedAttribution(attributionName);
      }

      final safeStart = start.clamp(0, text.length);
      final safeEnd = end.clamp(safeStart, text.length);
      if (safeEnd > safeStart) {
        spans.addAttribution(
          newAttribution: attribution,
          start: safeStart,
          end: safeEnd - 1,
        );
      }
    }

    return AttributedText(text, spans);
  }

  static DocumentNode? _nodeFromData(NoteNode node) {
    Map<String, dynamic> data;
    try {
      data = node.data.isNotEmpty
          ? jsonDecode(node.data) as Map<String, dynamic>
          : <String, dynamic>{};
    } catch (_) {
      try {
        data =
            jsonDecode(utf8.decode(base64Decode(node.data)))
                as Map<String, dynamic>;
      } catch (_) {
        data = <String, dynamic>{};
      }
    }

    switch (node.type) {
      case 'header':
        final level = data['level'] as int? ?? 1;
        NamedAttribution blockType = header1Attribution;
        if (level == 2) blockType = header2Attribution;
        if (level == 3) blockType = header3Attribution;
        if (level == 4) blockType = header4Attribution;
        if (level == 5) blockType = header5Attribution;
        if (level == 6) blockType = header6Attribution;
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
          metadata: {'blockType': blockType},
        );
      case 'blockquote':
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
          metadata: {'blockType': blockquoteAttribution},
        );
      case 'list_item':
        final typeStr = data['type'] as String? ?? 'unordered';
        return ListItemNode(
          id: node.id,
          itemType: typeStr == 'ordered'
              ? ListItemType.ordered
              : ListItemType.unordered,
          text: _deserializeAttributedText(data),
          indent: data['indent'] as int? ?? 0,
        );
      case 'paragraph':
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
        );
      case 'task':
        return TaskNode(
          id: node.id,
          text: _deserializeAttributedText(data),
          isComplete: data['completed'] == true || data['isComplete'] == true,
          indent: data['indent'] as int? ?? 0,
        );
      case 'divider':
        return HorizontalRuleNode(id: node.id);
      case 'attachment':
        final attachmentId = data['id'] as String? ?? node.id;
        return DocumentAttachmentNode(id: attachmentId);
      case 'image':
        return ImageNode(
          id: node.id,
          imageUrl: data['url'] as String? ?? '',
          altText: data['alt'] as String? ?? '',
        );
      default:
        return ParagraphNode(
          id: node.id,
          text: _deserializeAttributedText(data),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void suspendSync() {
    _document.removeListener(_onDocumentChanged);
  }

  void resumeSync() {
    _document.addListener(_onDocumentChanged);
  }

  Future<void> dispose() async {
    await flushNow();
    _debounceTimer?.cancel();
    _document.removeListener(_onDocumentChanged);
  }
}
