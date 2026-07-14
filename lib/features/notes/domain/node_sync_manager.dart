import 'dart:async';
import 'dart:developer' as dev;
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

class NodeSyncManager {
  NodeSyncManager({
    required MutableDocument document,
    this.onFlush,
  }) : _document = document {
    _document.addListener(_onDocumentChanged);
  }

  final MutableDocument _document;
  void Function(List<NodeOperation> ops)? onFlush;

  final List<NodeOperation> _pendingOps = [];
  Timer? _debounceTimer;

  /// IDs of nodes that have local changes not yet confirmed by the DB stream.
  /// Used by the editor controller to skip reactive updates for these nodes,
  /// preventing stale DB data from overwriting in-flight edits.
  final Set<String> locallyDirtyNodeIds = {};

  int _opSequence = 0;
  final Map<String, int> _dirtyNodeSequences = {};

  Future<void> _writeLock = Future.value();

  void _enqueueDbWrite(FutureOr<void> Function() action) {
    _writeLock = _writeLock.then((_) async {
      try {
        await action();
      } catch (e, stackTrace) {
        dev.log('SQLite write error: $e', name: 'NodeSyncManager', error: e, stackTrace: stackTrace, level: 1000);
      }
    });
  }



  void _onDocumentChanged(DocumentChangeLog changeLog) {
    debugPrint('[DEBUG-DIAG-EDIT] _onDocumentChanged: changes=${changeLog.changes.length} types=${changeLog.changes.map((c) => c.runtimeType).join(',')}');
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
    debugPrint('[DEBUG-DIAG-EDIT] _drainQueue: pending=${_pendingOps.length}');
    if (_pendingOps.isEmpty) return;

    final opsToProcess = List<NodeOperation>.from(_pendingOps);
    _pendingOps.clear();
    final snapshotSeq = _opSequence;

    // Clear dirty flags for flushed nodes only if no new ops arrived
    final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
    for (final id in flushedIds) {
      final seq = _dirtyNodeSequences[id];
      if (seq != null && seq <= snapshotSeq) {
        locallyDirtyNodeIds.remove(id);
        _dirtyNodeSequences.remove(id);
      }
    }

    if (opsToProcess.isNotEmpty) {
      debugPrint('[DEBUG-DIAG-EDIT] _drainQueue: calling onFlush with ${opsToProcess.length} ops');
      onFlush?.call(opsToProcess);
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
      onFlush?.call(opsToProcess);
    }

    return _writeLock;
  }

  static String? _opNodeId(NodeOperation op) => switch (op) {
    InsertOp(:final id) => id,
    UpdateOp(:final id) => id,
    MoveOp(:final id) => id,
    DeleteOp(:final id) => id,
  };



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
          'end': -1, // Will be filled when we find the end marker
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

        // Find the last opened span of this type that hasn't been closed
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

      // Ensure bounds are valid
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
