import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/database/database.dart';
import 'attachment_nodes.dart';
import 'task_entry.dart';

class NodeSyncManager {
  NodeSyncManager({
    required AppDatabase database,
    required String noteId,
    required MutableDocument document,
  })  : _db = database,
        _noteId = noteId,
        _document = document {
    _document.addListener(_onDocumentChanged);
  }

  final AppDatabase _db;
  final String _noteId;
  final MutableDocument _document;

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    for (final change in changeLog.changes) {
      if (change is NodeInsertedEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node == null) continue;
        final companion = _nodeToCompanion(node, change.insertionIndex);
        if (companion == null) continue;
        _db.into(_db.noteNodes).insertOnConflictUpdate(companion);
      } else if (change is NodeRemovedEvent) {
        (_db.delete(_db.noteNodes)..where((t) => t.id.equals(change.nodeId)))
            .go();
      } else if (change is NodeMovedEvent) {
        (_db.update(_db.noteNodes)
              ..where((t) => t.id.equals(change.nodeId)))
            .write(NoteNodesCompanion(position: Value(change.to)));
      } else if (change is NodeChangeEvent) {
        final node = _document.getNodeById(change.nodeId);
        if (node == null) continue;
        final index = _document.getNodeIndexById(change.nodeId);
        final companion = _nodeToCompanion(node, index);
        if (companion == null) continue;
        _db.into(_db.noteNodes).insertOnConflictUpdate(companion);
      }
    }
  }

  NoteNodesCompanion? _nodeToCompanion(DocumentNode node, int position) {
    final type = _nodeType(node);
    if (type == null) return null;

    final data = _nodeData(node);
    final now = DateTime.now();

    return NoteNodesCompanion.insert(
      id: node.id,
      noteId: _noteId,
      position: position,
      type: type,
      data: data,
      createdAt: now,
      updatedAt: now,
    );
  }

  String? _nodeType(DocumentNode node) {
    if (node is TaskNode) return 'task';
    if (node is AttachmentNode) return 'attachment';
    if (node is HorizontalRuleNode) return 'divider';
    if (node is TextNode) return 'paragraph';
    return null;
  }

  String _nodeData(DocumentNode node) {
    if (node is TextNode) {
      return jsonEncode({'text': node.text.toPlainText()});
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

  static DocumentNode? _nodeFromData(NoteNode node) {
    final data = node.data.isNotEmpty
        ? jsonDecode(node.data) as Map<String, dynamic>
        : <String, dynamic>{};
    final text = data['text'] as String? ?? '';

    switch (node.type) {
      case 'paragraph':
        return ParagraphNode(
          id: node.id,
          text: AttributedText(text),
        );
      case 'task':
        return TaskNode(
          id: node.id,
          text: AttributedText(text),
          isComplete: false,
        );
      case 'divider':
        return HorizontalRuleNode(id: node.id);
      case 'attachment':
        final attachmentId = data['id'] as String? ?? node.id;
        return DocumentAttachmentNode(id: attachmentId);
      default:
        return ParagraphNode(
          id: node.id,
          text: AttributedText(text),
        );
    }
  }

  static List<TaskEntry> extractTasks(List<NoteNode> nodes) {
    final tasks = <TaskEntry>[];
    for (final node in nodes) {
      if (node.type != 'task') continue;
      final data = node.data.isNotEmpty
          ? jsonDecode(node.data) as Map<String, dynamic>
          : <String, dynamic>{};
      final text = data['text'] as String? ?? '';
      tasks.add(TaskEntry(id: node.id, text: text, isComplete: false));
    }
    return tasks;
  }

  void dispose() {
    _document.removeListener(_onDocumentChanged);
  }
}
