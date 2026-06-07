/// Inbox screen.
///
/// The inbox is a single per-user note that the quick-capture FAB and
/// free-form text dumps land in. It is rendered with `SuperEditor` like
/// any other note, but the AppBar is stripped down to a fixed "Rascunho"
/// title and an "Organizar" affordance that hands the content off to the
/// agent — see `inbox_organize_sheet.dart` for that flow.
///
/// The markdown <-> `MutableDocument` round-trip is delegated to
/// `data/markdown_serializer.dart`; persistence (auto-save with debounce,
/// task sync) is managed by [InboxController].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart'
    hide serializeDocumentToMarkdown;

import 'package:supanotes/features/notes/data/markdown_serializer.dart';
import 'package:supanotes/features/notes/presentation/controllers/inbox_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
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
  String? _inboxId;

  @override
  void initState() {
    super.initState();
    ref.read(inboxControllerProvider.notifier).loadOrCreateInbox();
  }

  @override
  void dispose() {
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
    ref
        .read(inboxControllerProvider.notifier)
        .autoSave(id, markdown, tasks);
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
    final state = ref.watch(inboxControllerProvider);
    final inbox = state.asData?.value.inboxNote;
    final saveState = state.asData?.value.saveState ?? SaveState.idle;
    final hasContent = state.asData?.value.hasContent ?? false;

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
            SaveIndicator(state: saveState),
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
      await ref
          .read(inboxControllerProvider.notifier)
          .flushSave(id, markdown, tasks);
    }
    if (mounted) {
      context.pop();
    }
  }
}
