library;

import 'dart:async';
import 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';

import 'package:flutter/cupertino.dart' show CupertinoActionSheet, CupertinoActionSheetAction, showCupertinoModalPopup;
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/notes/data/attachments_repository.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/features/notes/data/user_note_preferences_repository.dart';
import 'package:supanotes/features/notes/domain/note_strings.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/share_note_sheet.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String noteId;

  const NoteEditorScreen({super.key, required this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  Future<void> _openTaskActions(
    TaskModel? task,
    Future<void> Function() flushSnapshot,
  ) async {
    await flushSnapshot();
    if (!mounted || task == null) return;

    await TaskMetadataSheet.show(context, noteId: task.noteId, task: task);
  }

  Future<void> _showMoreMenu(
    BuildContext context,
    WidgetRef ref,
    NoteModel note,
    bool hideCompleted,
    INotesRepository repo,
  ) async {
    final isOwner = note.isOwner;
    final items = [
      if (isOwner)
        AdaptivePopupMenuItem<String>(
          label: NoteStrings.shareLabel,
          icon: Icons.share_outlined,
          value: 'share',
        ),
      AdaptivePopupMenuItem<String>(
        label: hideCompleted
            ? NoteStrings.showCompleted
            : NoteStrings.hideCompleted,
        icon: hideCompleted ? Icons.visibility : Icons.visibility_off,
        value: 'hide_completed',
      ),
      if (isOwner)
        AdaptivePopupMenuItem<String>(
          label: note.collapseImages ? 'Expandir imagens' : 'Colapsar imagens',
          icon: note.collapseImages ? Icons.image : Icons.image_outlined,
          value: 'collapse_images',
        ),
    ];

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final selected = await showCupertinoModalPopup<int>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          actions: [
            for (var i = 0; i < items.length; i++)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.of(ctx).pop(i),
                child: Text(items[i].label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(),
            isDefaultAction: true,
            child: const Text('Cancelar'),
          ),
        ),
      );
      if (selected != null && context.mounted) {
        final val = items[selected].value;
        if (val != null) {
          _handleMenuValue(context, ref, val, note, hideCompleted, repo);
        }
      }
    } else {
      final renderBox = context.findRenderObject() as RenderBox?;
      final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
      final size = renderBox?.size ?? Size.zero;

      final selectedValue = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          offset.dx + size.width,
          offset.dy + 56,
          offset.dx + size.width,
          offset.dy,
        ),
        items: [
          for (final item in items)
            PopupMenuItem<String>(
              value: item.value,
              child: Row(
                children: [
                  Icon(item.icon as IconData?),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item.label),
                  ),
                ],
              ),
            ),
        ],
      );
      if (selectedValue != null && context.mounted) {
        _handleMenuValue(context, ref, selectedValue, note, hideCompleted, repo);
      }
    }
  }

  Future<void> _handleMenuValue(
    BuildContext context,
    WidgetRef ref,
    String value,
    NoteModel note,
    bool hideCompleted,
    INotesRepository repo,
  ) async {
    switch (value) {
      case 'share':
        await showAppBottomSheet(
          context: context,
          builder: (_) => ShareNoteSheet(noteId: widget.noteId),
        );
      case 'hide_completed':
        final userId = ref.read(currentUserIdProvider);
        if (userId != null) {
          await ref
              .read(userNotePreferencesRepositoryProvider)
              .setHideCompleted(
                userId,
                widget.noteId,
                !hideCompleted,
              );
        }
      case 'collapse_images':
        await repo.updateNote(
          widget.noteId,
          collapseImages: !note.collapseImages,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(notesRepositoryProvider);
    final combinedAsync = ref.watch(combinedNoteEditorStateProvider(widget.noteId));

    return combinedAsync.when(
      data: (data) {
        final (nodes, noteWithTasks) = data;
        final note = noteWithTasks.note;
        if (note == null) {
          return AdaptiveScaffold(
            body: SafeArea(child: Center(child: Text(NoteStrings.errorNotFound))),
          );
        }

        final tasksMap = noteWithTasks.taskById;

        final isReadOnly = note.isReadOnly;
        final hideCompleted = note.hideCompleted;

        return AdaptiveScaffold(
          resizeToAvoidBottomInset: false,
          appBar: AdaptiveAppBar(
            title: isReadOnly
                ? '${NoteStrings.sharedByPrefix} ${note.sharedByEmail}'
                : null,
            actions: [
              AdaptiveAppBarAction(
                icon: Icons.more_vert,
                iosSymbol: 'ellipsis',
                onPressed: () => _showMoreMenu(context, ref, note, hideCompleted, repo),
              ),
              if (!isReadOnly)
                AdaptiveAppBarAction(
                  icon: Icons.check,
                  iosSymbol: 'checkmark',
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    SystemChannels.textInput.invokeMethod(
                      'TextInput.hide',
                    );
                  },
                ),
            ],
          ),
          body: NoteEditor(
            noteId: widget.noteId,
            nodes: nodes,
            taskMetadata: tasksMap,
            hideCompleted: hideCompleted,
            collapseImages: note.collapseImages,
            isReadOnly: isReadOnly,
            delegate: NoteEditorDelegate(
              emptyNoteExit: (noteId) => defaultEmptyNoteExit(repo, noteId),
              onTaskLongPress: isReadOnly
                  ? null
                  : (task, flushSnapshot) =>
                        _openTaskActions(task, flushSnapshot),
              onTaskComplete: (taskId) =>
                  TaskSnackBarHelper.completeTaskWithFeedback(
                    onComplete: () => ref
                        .read(tasksRepositoryProvider)
                        .completeTask(taskId),
                    onUndo: (previousDue) => ref
                        .read(tasksRepositoryProvider)
                        .reopenTask(taskId, originalDueDate: previousDue),
                  ),
              onTaskReopen: (taskId) =>
                  ref.read(tasksRepositoryProvider).reopenTask(taskId),
              onUploadFile: isReadOnly
                  ? null
                  : (id, noteId, filePath, mimeType) => ref
                        .read(attachmentsRepositoryProvider)
                        .upload(
                          id: id,
                          noteId: noteId,
                          file: File(filePath),
                          mimeType: mimeType,
                        ),
            ),
          ),
        );
      },
      loading: () =>
          const AdaptiveScaffold(body: SafeArea(child: Center(child: CircularProgressIndicator()))),
      error: (error, _) =>
          AdaptiveScaffold(body: SafeArea(child: Center(child: Text('Error: $error')))),
    );
  }
}
