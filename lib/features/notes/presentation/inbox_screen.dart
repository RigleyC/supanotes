/// Inbox screen.
///
/// The inbox is a single per-user note that the quick-capture FAB and
/// free-form text dumps land in. It is rendered with `SuperEditor` like
/// any other note, but the AppBar is stripped down to a fixed "Rascunho"
/// title and an "Organizar" affordance that hands the content off to the
/// agent — see `inbox_organize_sheet.dart` for that flow.
///
/// The Markdown <-> `MutableDocument` round-trip is delegated to
/// [parseMarkdownToDocument] / [serializeDocumentToMarkdown] in
/// `data/markdown_serializer.dart`; the only thing this file owns is
/// `super_editor` wiring, the debounced auto-save, and the task-table
/// sync. Anything that needs to read or mutate the inbox row goes
/// through [NotesLocalRepository].
library;

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart'
    hide serializeDocumentToMarkdown;

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/data/local/notes_local_repository.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/save_indicator.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  MutableDocument? _document;
  Editor? _editor;
  MutableDocumentComposer? _composer;
  FocusNode? _focusNode;
  String? _inboxId;
  bool _hasContent = false;
  Timer? _debounceTimer;
  SaveState _saveState = SaveState.idle;

  @override
  void initState() {
    super.initState();
    _loadInbox();
  }

  Future<void> _loadInbox() async {
    final note =
        await ref.read(notesLocalRepositoryProvider).getOrCreateInboxNote();
    if (!mounted) return;
    _inboxId = note.id;
    _document = parseMarkdownToDocument(note.content);
    _composer = MutableDocumentComposer();
    _editor = createDefaultDocumentEditor(
      document: _document!,
      composer: _composer!,
    );
    _focusNode = FocusNode();
    _hasContent = note.content.trim().isNotEmpty;
    _document!.addListener(_onDocumentChanged);
    setState(() {});
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    if (!mounted) return;
    final doc = _document;
    if (doc == null) return;
    final hasContent = doc
        .toList()
        .whereType<TextNode>()
        .any((n) => n.text.toPlainText().trim().isNotEmpty);
    if (hasContent != _hasContent) {
      setState(() => _hasContent = hasContent);
    }
    _setSaveState(SaveState.saving);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      _flushSave,
    );
  }

  Future<void> _flushSave() async {
    final doc = _document;
    final id = _inboxId;
    if (doc == null || id == null) return;
    final markdown = serializeDocumentToMarkdown(doc);
    try {
      await _syncTasks(doc, id);
      await ref
          .read(notesLocalRepositoryProvider)
          .updateNoteContent(id, markdown);
      _setSaveState(SaveState.saved);
    } catch (_) {
      _setSaveState(SaveState.error);
    }
  }

  Future<void> _syncTasks(MutableDocument doc, String noteId) async {
    final tasksRepo = ref.read(tasksLocalRepositoryProvider);
    final currentTasks = await tasksRepo.watchNoteTasks(noteId).first;
    final currentIds = currentTasks.map((t) => t.id).toSet();
    final docIds = <String>{};
    for (final node in doc) {
      if (node is TaskNode) {
        final text = node.text.toPlainText();
        docIds.add(node.id);
        if (currentIds.contains(node.id)) {
          await tasksRepo.updateTask(TasksCompanion(
            id: drift.Value(node.id),
            title: drift.Value(text),
            status: drift.Value(node.isComplete ? 'completed' : 'pending'),
          ));
        } else {
          await tasksRepo.createTask(
            id: node.id,
            noteId: noteId,
            title: text,
            position: 0,
            status: node.isComplete ? 'completed' : 'pending',
          );
        }
      }
    }
    final removed = currentIds.difference(docIds);
    for (final id in removed) {
      await tasksRepo.deleteTask(id);
    }
  }

  Future<void> _onOrganizePressed() async {
    try {
      final applied = await showInboxOrganizeSheet(context);
      if (!mounted) return;
      if (applied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rascunho organizado')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao organizar: $e')),
      );
    }
  }

  void _setSaveState(SaveState state) {
    if (!mounted) return;
    setState(() => _saveState = state);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _document?.removeListener(_onDocumentChanged);
    _document?.dispose();
    _composer?.dispose();
    _focusNode?.dispose();
    super.dispose();
  }

  Future<void> _saveAndPop() async {
    _debounceTimer?.cancel();
    final doc = _document;
    final id = _inboxId;
    if (doc != null && id != null) {
      await _flushSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _document;
    final editor = _editor;
    final composer = _composer;
    if (doc == null || editor == null || composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _saveAndPop().then((_) {
          if (context.mounted) {
            context.pop();
          }
        });
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Rascunho'),
        actions: [
          SaveIndicator(state: _saveState),
          if (_hasContent)
            TextButton(
              onPressed: _onOrganizePressed,
              child: const Text('Organizar'),
            ),
        ],
      ),
      body: Column(
        children: [
          NoteToolbar(editor: editor, composer: composer),
          Expanded(
            child: SuperEditor(
              editor: editor,
              focusNode: _focusNode,
              stylesheet: defaultStylesheet.copyWith(
                documentPadding: const EdgeInsets.all(AppSpacing.md),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
