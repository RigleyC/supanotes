library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/inbox_organize_sheet.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_toolbar.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/shared/theme/app_typography.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final _controller = NoteEditorController(
    editableTitle: true,
    contentSave: defaultContentSave,
    titleSave: defaultTitleSave,
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
    _controller.dispose();
    super.dispose();
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
    // Incondicional: o Riverpod exige que ref.watch seja chamado em
    // todo build() para manter a assinatura viva.
    final asyncValue = ref.watch(inboxProvider);

    if (_controller.document == null) {
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
        _controller.bind(ref, inbox.id);
        _controller.init(content: inbox.content, title: inbox.title);
      }
    }

    if (_controller.document == null ||
        _controller.editor == null ||
        _controller.composer == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasContent = _controller.document!.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _controller.flushBeforePop();
        if (!context.mounted) return;
        context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: TextField(
            controller: _controller.titleController,
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
          actions: [
            if (hasContent)
              TextButton(
                onPressed: _onOrganizePressed,
                child: const Text('Organizar'),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SuperEditor(
                editor: _controller.editor!,
                focusNode: _controller.focusNode,
                stylesheet: defaultStylesheet.copyWith(
                  documentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
                componentBuilders: [
                  ...defaultComponentBuilders,
                  CustomTaskComponentBuilder(_controller.editor!),
                ],
              ),
            ),
            NoteToolbar(
              editor: _controller.editor!,
              composer: _controller.composer!,
            ),
          ],
        ),
      ),
    );
  }
}
