library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart'
    hide serializeDocumentToMarkdown;

import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/domain/task_entry.dart';
import 'package:supanotes/features/notes/presentation/controllers/editor_status_notifier.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/features/notes/presentation/widgets/save_indicator.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

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
  Timer? _debounceTimer;
  String? _inboxId;

  @override
  void initState() {
    super.initState();
    ref.invalidate(inboxProvider);
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

  void _onDocumentChanged(DocumentChangeLog _) {
    final doc = _document;
    final id = _inboxId;
    if (doc == null || id == null) return;
    final markdown = serializeDocumentToMarkdown(doc);
    final tasks = _extractTasks(doc);
    _debounceTimer?.cancel();
    ref.read(editorStatusProvider.notifier).saving();
    _debounceTimer = Timer(
      Duration(milliseconds: AppConstants.autoSaveDebounceMs),
      () => _flushSave(id, markdown, tasks),
    );
  }

  List<TaskEntry> _extractTasks(MutableDocument doc) {
    final tasks = <TaskEntry>[];
    for (final node in doc) {
      if (node is TaskNode) {
        tasks.add(TaskEntry(
          id: node.id,
          text: node.text.toPlainText(),
          isComplete: node.isComplete,
        ));
      }
    }
    return tasks;
  }

  Future<void> _flushSave(String noteId, String markdown, List<TaskEntry> tasks) async {
    _debounceTimer?.cancel();
    try {
      await ref.read(notesRepositoryProvider).syncTasksFromDocument(noteId, tasks);
      await ref
          .read(notesRepositoryProvider)
          .updateNote(noteId, content: markdown);
      ref.read(editorStatusProvider.notifier).saved();
    } catch (_) {
      ref.read(editorStatusProvider.notifier).errored();
    }
  }

  Future<void> _onOrganizePressed() async {
    try {
      final applied = await showAppBottomSheet<bool>(
        context: context,
        builder: (_) => const InboxOrganizeSheet(),
      );
      if (!mounted) return;
      if (applied == true) {
        AppMessenger.showSuccess(context, 'Rascunho organizado');
      }
    } catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, 'Erro ao organizar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(inboxProvider);
    final editorStatus = ref.watch(editorStatusProvider);
    final inbox = inboxAsync.asData?.value;
    final hasContent = inbox != null && inbox.content.isNotEmpty;

    if (inbox != null && _document == null) {
      _inboxId = inbox.id;
      _document = parseMarkdownToDocument(inbox.content);
      _composer = MutableDocumentComposer();
      _editor = createDefaultDocumentEditor(
        document: _document!,
        composer: _composer!,
      );
      _focusNode = FocusNode();
      _document!.addListener(_onDocumentChanged);
    }

    if (_document == null || _editor == null || _composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _saveAndPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rascunho'),
          actions: [
            SaveIndicator(state: editorStatus),
            if (hasContent)
              TextButton(
                onPressed: _onOrganizePressed,
                child: const Text('Organizar'),
              ),
          ],
        ),
        body: Column(
          children: [
            NoteToolbar(editor: _editor!, composer: _composer!),
            Expanded(
              child: SuperEditor(
                editor: _editor!,
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

  Future<void> _saveAndPop() async {
    final doc = _document;
    final id = _inboxId;
    if (doc != null && id != null) {
      final markdown = serializeDocumentToMarkdown(doc);
      final tasks = _extractTasks(doc);
      await _flushSave(id, markdown, tasks);
    }
    if (mounted) {
      context.pop();
    }
  }
}
