import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_editor/super_editor.dart';

import '../data/local/notes_local_repository.dart';
import '../../tasks/data/local/tasks_local_repository.dart';
import '../../../core/database/database.dart';
import 'package:drift/drift.dart' as drift;

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  MutableDocument? _document;
  Editor? _editor;
  MutableDocumentComposer? _composer;
  Timer? _debounceTimer;
  String? _inboxId;

  @override
  void initState() {
    super.initState();
    _loadInbox();
  }

  Future<void> _loadInbox() async {
    final note = await ref.read(notesLocalRepositoryProvider).getOrCreateInboxNote();
    _inboxId = note.id;
    
    if (note.content.isEmpty) {
      _document = MutableDocument.empty();
    } else {
      final lines = note.content.split('\n');
      final nodes = <DocumentNode>[];
      for (final line in lines) {
        if (line.isEmpty) continue;
        if (line.trim().startsWith('- [ ] ') || line.trim().startsWith('- [x] ')) {
          final isComplete = line.trim().startsWith('- [x] ');
          var text = line.trim().substring(6);
          String id = Editor.createNodeId();
          
          final idMatch = RegExp(r'<!-- task:(.*?) -->').firstMatch(text);
          if (idMatch != null) {
            id = idMatch.group(1)!;
            text = text.replaceFirst(idMatch.group(0)!, '').trim();
          }

          nodes.add(TaskNode(
            id: id,
            text: AttributedText(text),
            isComplete: isComplete,
          ));
        } else {
          nodes.add(ParagraphNode(
            id: Editor.createNodeId(),
            text: AttributedText(line),
          ));
        }
      }
      if (nodes.isEmpty) {
        nodes.add(ParagraphNode(id: Editor.createNodeId(), text: AttributedText('')));
      }
      _document = MutableDocument(nodes: nodes);
    }
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(document: _document!, composer: _composer!);
    _document!.addListener(_onDocumentChanged);
    setState(() {});
  }

  void _onDocumentChanged(DocumentChangeLog changeLog) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      _saveNote();
    });
  }

  Future<void> _saveNote() async {
    if (_document == null || _inboxId == null) return;
    
    String content = '';
    final tasksRepo = ref.read(tasksLocalRepositoryProvider);
    final currentTasks = await tasksRepo.watchNoteTasks(_inboxId!).first;
    final currentTaskIds = currentTasks.map((t) => t.id).toSet();
    final documentTaskIds = <String>{};

    for (final node in _document!) {
      if (node is TaskNode) {
        final text = node.text.toPlainText();
        content += '- [${node.isComplete ? 'x' : ' '}] $text <!-- task:${node.id} -->\n';
        documentTaskIds.add(node.id);

        if (currentTaskIds.contains(node.id)) {
          await tasksRepo.updateTask(TasksCompanion(
            id: drift.Value(node.id),
            title: drift.Value(text),
            status: drift.Value(node.isComplete ? 'completed' : 'pending'),
          ));
        } else {
          await tasksRepo.createTask(
            id: node.id,
            noteId: _inboxId!,
            title: text,
            position: 0,
            status: node.isComplete ? 'completed' : 'pending',
          );
        }
      } else if (node is TextNode) {
        content += '${node.text.toPlainText()}\n';
      }
    }

    final removedTasks = currentTaskIds.difference(documentTaskIds);
    for (final id in removedTasks) {
      await tasksRepo.deleteTask(id);
    }

    await ref.read(notesLocalRepositoryProvider).updateNoteContent(_inboxId!, content.trim());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _document?.removeListener(_onDocumentChanged);
    _document?.dispose();
    _composer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_document == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Organização com Agent será implementada em breve!')),
              );
            },
            child: const Text('Organizar', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: SuperEditor(
        editor: _editor!,
        stylesheet: defaultStylesheet.copyWith(
          documentPadding: const EdgeInsets.all(24),
        ),
      ),
    );
  }
}
