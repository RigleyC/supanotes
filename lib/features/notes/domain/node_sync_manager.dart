import 'dart:async';
import 'dart:developer' as dev;
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/database/database.dart';
import 'attachment_nodes.dart';
import 'note_display_text.dart';
import 'task_entry.dart';

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
    required AppDatabase database,
    required String noteId,
    required String userId,
    required MutableDocument document,
  }) : _db = database,
       _noteId = noteId,
       _userId = userId,
       _document = document {
    _document.addListener(_onDocumentChanged);
  }

  final AppDatabase _db;
  final String _noteId;
  final String _userId;
  final MutableDocument _document;

  final List<NodeOperation> _pendingOps = [];
  Timer? _debounceTimer;

  /// IDs of nodes that have local changes not yet confirmed by the DB stream.
  /// Used by the editor controller to skip reactive updates for these nodes,
  /// preventing stale DB data from overwriting in-flight edits.
  final Set<String> locallyDirtyNodeIds = {};

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

  Future<double> _calculatePositionForInsert(String nodeId, int insertionIndex) async {
    final dbNodes = await (_db.select(_db.noteNodes)
      ..where((t) => t.noteId.equals(_noteId))
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.position, mode: OrderingMode.asc)])
    ).get();

    if (dbNodes.isEmpty) {
      return 1.0;
    }

    if (insertionIndex == 0) {
      return dbNodes.first.position / 2.0;
    }

    if (insertionIndex >= dbNodes.length) {
      return dbNodes.last.position + 1.0;
    }

    final prevPos = dbNodes[insertionIndex - 1].position;
    final nextPos = dbNodes[insertionIndex].position;
    return (prevPos + nextPos) / 2.0;
  }

  Future<double> _calculatePositionForMove(String nodeId, int toIndex) async {
    final dbNodes = await (_db.select(_db.noteNodes)
      ..where((t) => t.noteId.equals(_noteId))
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.id.equals(nodeId).not())
      ..orderBy([(t) => OrderingTerm(expression: t.position, mode: OrderingMode.asc)])
    ).get();

    if (dbNodes.isEmpty) {
      return 1.0;
    }

    if (toIndex == 0) {
      return dbNodes.first.position / 2.0;
    }

    if (toIndex >= dbNodes.length) {
      return dbNodes.last.position + 1.0;
    }

    final prevPos = dbNodes[toIndex - 1].position;
    final nextPos = dbNodes[toIndex].position;
    return (prevPos + nextPos) / 2.0;
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    for (final change in changeLog.changes) {
      if (change is NodeInsertedEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node != null) {
          _pendingOps.add(InsertOp(change.nodeId, node, change.insertionIndex));
          locallyDirtyNodeIds.add(change.nodeId);
        }
      } else if (change is NodeRemovedEvent) {
        _pendingOps.add(DeleteOp(change.nodeId));
        locallyDirtyNodeIds.add(change.nodeId);
      } else if (change is NodeMovedEvent) {
        _pendingOps.add(MoveOp(change.nodeId, change.from, change.to));
        locallyDirtyNodeIds.add(change.nodeId);
      } else if (change is NodeChangeEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node != null) {
          _pendingOps.add(UpdateOp(change.nodeId, node));
          locallyDirtyNodeIds.add(change.nodeId);
        }
      }
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _enqueueDbWrite(_drainQueue);
    });
  }

  String _buildContentSnapshot() {
    return _document
        .where((n) => n is TextNode || n is TaskNode)
        .map((n) {
          if (n is TaskNode) {
            return '- [${n.isComplete ? 'x' : ' '}] ${n.text.toPlainText()}';
          }
          return (n as TextNode).text.toPlainText();
        })
        .join('\n');
  }

  Future<void> _flushNoteExcerptFromSnapshot(String fullText, DateTime now) async {
    final excerpt = deriveNoteExcerpt(fullText);

    await (_db.update(_db.notes)..where((t) => t.id.equals(_noteId))).write(
      NotesCompanion(
        content: Value(fullText),
        excerpt: Value(excerpt),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> _applyOpsTransaction(
    List<NodeOperation> opsToProcess,
    DateTime now,
    String snapshotText,
  ) async {
    await _db.transaction(() async {
      for (final op in opsToProcess) {
        switch (op) {
          case InsertOp():
            final position = await _calculatePositionForInsert(op.id, op.index);
            final companion = _nodeToCompanion(op.node, position);
            if (companion != null) {
              await _db.into(_db.noteNodes).insertOnConflictUpdate(companion);
            }
            if (op.node is TaskNode) {
              final taskNode = op.node as TaskNode;
              final taskCompanion = TasksCompanion.insert(
                id: op.id,
                userId: _userId,
                noteId: _noteId,
                title: taskNode.text.toPlainText(),
                status: taskNode.isComplete ? 'done' : 'open',
                position: Value(position),
                createdAt: now,
                updatedAt: now,
                isDirty: const Value(true),
                deletedAt: const Value(null),
              );
              await _db.into(_db.tasks).insertOnConflictUpdate(taskCompanion);
            }
            break;

          case UpdateOp():
            final existingNode = await (_db.select(_db.noteNodes)
              ..where((t) => t.id.equals(op.id))).getSingleOrNull();
            final position = existingNode?.position ?? 0.0;

            final companion = _nodeToCompanion(op.node, position);
            if (companion != null) {
              await _db.into(_db.noteNodes).insertOnConflictUpdate(companion);
            }
            if (op.node is TaskNode) {
              final taskNode = op.node as TaskNode;
              final taskCompanion = TasksCompanion.insert(
                id: op.id,
                userId: _userId,
                noteId: _noteId,
                title: taskNode.text.toPlainText(),
                status: taskNode.isComplete ? 'done' : 'open',
                position: Value(position),
                createdAt: now,
                updatedAt: now,
                isDirty: const Value(true),
                deletedAt: const Value(null),
              );
              await _db.into(_db.tasks).insertOnConflictUpdate(taskCompanion);
            }
            break;

          case MoveOp():
            final position = await _calculatePositionForMove(op.id, op.to);

            await (_db.update(_db.noteNodes)..where((t) => t.id.equals(op.id))).write(
              NoteNodesCompanion(
                position: Value(position),
                isDirty: const Value(true),
              ),
            );
            await (_db.update(_db.tasks)..where((t) => t.id.equals(op.id))).write(
              TasksCompanion(
                position: Value(position),
                isDirty: const Value(true),
              ),
            );
            break;

          case DeleteOp():
            await (_db.update(_db.noteNodes)..where((t) => t.id.equals(op.id))).write(
              NoteNodesCompanion(deletedAt: Value(now), isDirty: const Value(true)),
            );
            await (_db.update(_db.tasks)..where((t) => t.id.equals(op.id))).write(
              TasksCompanion(deletedAt: Value(now), isDirty: const Value(true)),
            );
            break;
        }
      }

      await _flushNoteExcerptFromSnapshot(snapshotText, now);
    });
  }

  Future<void> _drainQueue() async {
    if (_pendingOps.isEmpty) return;

    final opsToProcess = List<NodeOperation>.from(_pendingOps);
    _pendingOps.clear();

    final now = DateTime.now().toUtc();
    final snapshotText = _buildContentSnapshot();

    await _applyOpsTransaction(opsToProcess, now, snapshotText);

    // Clear dirty flags for flushed nodes only if no new ops arrived
    // during the transaction. If new ops arrived, those IDs stay dirty.
    final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
    final stillPendingIds = _pendingOps.map(_opNodeId).whereType<String>().toSet();
    locallyDirtyNodeIds.removeAll(flushedIds.difference(stillPendingIds));
  }

  void flushNow() {
    _debounceTimer?.cancel();
    if (_pendingOps.isEmpty) return;

    final opsToProcess = List<NodeOperation>.from(_pendingOps);
    _pendingOps.clear();

    final now = DateTime.now().toUtc();
    final snapshotText = _buildContentSnapshot();

    _enqueueDbWrite(() async {
      await _applyOpsTransaction(opsToProcess, now, snapshotText);
      final flushedIds = opsToProcess.map(_opNodeId).whereType<String>().toSet();
      final stillPendingIds = _pendingOps.map(_opNodeId).whereType<String>().toSet();
      locallyDirtyNodeIds.removeAll(flushedIds.difference(stillPendingIds));
    });
  }

  static String? _opNodeId(NodeOperation op) => switch (op) {
    InsertOp(:final id) => id,
    UpdateOp(:final id) => id,
    MoveOp(:final id) => id,
    DeleteOp(:final id) => id,
  };

  NoteNodesCompanion? _nodeToCompanion(DocumentNode node, double position) {
    final type = _nodeType(node);
    if (type == null) return null;

    final data = nodeData(node);
    final now = DateTime.now();

    return NoteNodesCompanion.insert(
      id: node.id,
      noteId: _noteId,
      position: position,
      type: type,
      data: data,
      createdAt: now,
      updatedAt: now,
      isDirty: const Value(true),
      deletedAt: const Value(null),
    );
  }

  String? _nodeType(DocumentNode node) {
    if (node is TaskNode) return 'task';
    if (node is AttachmentNode) return 'attachment';
    if (node is HorizontalRuleNode) return 'divider';
    if (node is ParagraphNode) {
      final blockType = node.metadata['blockType'];
      if (blockType == header1Attribution ||
          blockType == header2Attribution ||
          blockType == header3Attribution ||
          blockType == header4Attribution ||
          blockType == header5Attribution ||
          blockType == header6Attribution) {
        return 'header';
      }
      if (blockType == blockquoteAttribution) {
        return 'blockquote';
      }
      return 'paragraph';
    }
    if (node is ListItemNode) return 'list_item';
    if (node is ImageNode) return 'image';
    return null;
  }

  static Map<String, dynamic> _serializeAttributedText(AttributedText text) {
    final spansList = <Map<String, dynamic>>[];
    for (final span in text.spans.markers) {
      if (span.isStart) {
        String attributionName;
        final attribution = span.attribution;
        if (attribution == boldAttribution) {
          attributionName = 'bold';
        } else if (attribution == italicsAttribution) {
          attributionName = 'italics';
        } else if (attribution == strikethroughAttribution) {
          attributionName = 'strikethrough';
        } else if (attribution == underlineAttribution) {
          attributionName = 'underline';
        } else if (attribution is LinkAttribution) {
          attributionName = 'link:${attribution.url.toString()}';
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
        if (attribution == boldAttribution) {
          attributionName = 'bold';
        } else if (attribution == italicsAttribution) {
          attributionName = 'italics';
        } else if (attribution == strikethroughAttribution) {
          attributionName = 'strikethrough';
        } else if (attribution == underlineAttribution) {
          attributionName = 'underline';
        } else if (attribution is LinkAttribution) {
          attributionName = 'link:${attribution.url.toString()}';
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
        'completed': node.isComplete,
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
      return MutableDocument.empty();
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

      if (attributionName == null || start == null || end == null || end == -1)
        continue;

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

  static List<TaskEntry> extractTasks(List<NoteNode> nodes) {
    final tasks = <TaskEntry>[];
    for (final node in nodes) {
      if (node.type != 'task') continue;
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
      final text = data['text'] as String? ?? '';
      tasks.add(TaskEntry(id: node.id, text: text, isComplete: false));
    }
    return tasks;
  }

  void suspendSync() {
    _document.removeListener(_onDocumentChanged);
  }

  void resumeSync() {
    _document.addListener(_onDocumentChanged);
  }

  void dispose() {
    flushNow();
    _debounceTimer?.cancel();
    _document.removeListener(_onDocumentChanged);
  }
}
