library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/agent/domain/destination_type.dart';
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/shared/theme/app_typography.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  NoteEditorController? _controller;

  NoteEditorController _controllerOrCreate() =>
      _controller ??= NoteEditorController(
        editableTitle: true,
        snapshotSave: (noteId, title, markdown, tasks) =>
            defaultSnapshotSave(ref, noteId, title, markdown, tasks),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(notesRepositoryProvider).ensureInbox());
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onOrganizePressed() async {
    final result = await showInboxOrganizeSheet(context);
    if (!mounted || result == null) return;

    final created = result.items
        .where((i) => i.accepted && i.destinationType == DestinationType.newNote)
        .length;
    final moved = result.items
        .where((i) => i.accepted && i.destinationType == DestinationType.existingNote)
        .length;
    final kept = result.items
        .where((i) => i.accepted && i.destinationType == DestinationType.keep)
        .length;

    AppMessenger.showSuccess(
      context,
      '$created nota(s) criada(s), $moved atualizada(s), $kept mantida(s)',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Incondicional: o Riverpod exige que ref.watch seja chamado em
    // todo build() para manter a assinatura viva.
    final asyncValue = ref.watch(inboxProvider);
    final controller = _controllerOrCreate();

    if (controller.document == null) {
      if (asyncValue.isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (asyncValue.hasError) {
        return Scaffold(
          body: Center(child: Text('Error: ${asyncValue.error}')),
        );
      }
      final inbox = asyncValue.asData?.value;
      if (inbox != null) {
        controller.bind(inbox.id);
        controller.init(content: inbox.content, title: inbox.title);
      }
    }

    if (controller.document == null ||
        controller.editor == null ||
        controller.composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasContent = controller.document!.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await controller.flushBeforePop();
        if (!context.mounted) return;
        context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: TextField(
            controller: controller.titleController,
            decoration: const InputDecoration(
              border: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
              hintText: 'Sem título',
            ),
            style: AppTypography.textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SuperEditor(
                editor: controller.editor!,
                focusNode: controller.focusNode,
                stylesheet: defaultStylesheet.copyWith(
                 documentPadding:  EdgeInsets.zero,
                ),
                componentBuilders: [
                  ...defaultComponentBuilders,
                  CustomTaskComponentBuilder(controller.editor!),
                ],
              ),
            ),
            NoteToolbar(
              editor: controller.editor!,
              composer: controller.composer!,
            ),
          ],
        ),
        floatingActionButton: _buildOrganizeFab(hasContent),
      ),
    );
  }

  Widget? _buildOrganizeFab(bool show) {
    if (!show) return null;
    return FloatingActionButton(
      onPressed: _onOrganizePressed,
      child: const Icon(Icons.auto_awesome),
    );
  }
}
