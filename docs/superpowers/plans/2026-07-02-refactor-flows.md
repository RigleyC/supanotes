# Refactor Share Note and Task Attributes Flows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the UI sheets for note sharing and task editing to use Riverpod controllers for state management, eliminate code duplication, and enforce UI component/string conventions.

**Architecture:** We will create a `TaskController` to handle task mutations, update `ShareNoteController` to handle revocation, remove redundant UI logic and manual state orchestration from sheets, consolidate `TaskMetadataSheet` into `TaskEditSheet`, and replace raw `TextField`/`DropdownButton` with `AppInput` where possible or use the project's standard dialogs.

**Tech Stack:** Flutter, Riverpod

---

## User Review Required
> [!WARNING]
> This plan will delete `TaskMetadataSheet` completely. Any external calls to it will be replaced by `TaskEditSheet.show(..., readOnlyTitle: true)`. The `TaskEditSheet` will also be fixed since it currently doesn't even render the title field.

---

### Task 1: Create TaskController

**Files:**
- Create: `lib/features/tasks/presentation/controllers/task_controller.dart`

- [ ] **Step 1: Write TaskController implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/tasks_repository.dart';
import '../../domain/task_model.dart';
import '../../domain/task_recurrence.dart';

final taskControllerProvider = AsyncNotifierProvider.autoDispose<TaskController, void>(
  TaskController.new,
);

class TaskController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> createTask({
    required String noteId,
    required String title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(tasksRepositoryProvider).createTask(
            noteId: noteId,
            title: title,
            dueDate: dueDate,
            recurrence: recurrence,
          ),
    );
  }

  Future<void> updateTask({
    required String taskId,
    required String title,
    DateTime? dueDate,
    TaskRecurrence? recurrence,
    bool clearDueDate = false,
    bool clearRecurrence = false,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(tasksRepositoryProvider).updateTask(
            taskId,
            title: title,
            dueDate: dueDate,
            recurrence: recurrence,
            clearDueDate: clearDueDate,
            clearRecurrence: clearRecurrence,
          ),
    );
  }

  Future<void> deleteTask(String taskId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(tasksRepositoryProvider).deleteTask(taskId),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/tasks/presentation/controllers/task_controller.dart
git commit -m "feat(tasks): create TaskController for mutations"
```

### Task 2: Refactor ShareNoteController to handle revocation

**Files:**
- Modify: `lib/features/notes/presentation/controllers/share_note_controller.dart`

- [ ] **Step 1: Add revoke method**
Replace the content of `share_note_controller.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/shares_repository.dart';
import '../../domain/share_permission.dart';

final shareNoteControllerProvider =
    AsyncNotifierProvider.autoDispose<ShareNoteController, void>(
  ShareNoteController.new,
);

class ShareNoteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> share({
    required String noteId,
    required String email,
    required SharePermission permission,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(sharesRepositoryProvider).shareNote(
            noteId: noteId,
            email: email,
            permission: permission,
          ),
    );
  }

  Future<void> revoke({
    required String noteId,
    required String userId,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(sharesRepositoryProvider).deleteShare(
            noteId: noteId,
            userId: userId,
          ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/controllers/share_note_controller.dart
git commit -m "refactor(shares): add revoke method to ShareNoteController"
```

### Task 3: Fix and Refactor TaskEditSheet

**Files:**
- Modify: `lib/features/tasks/presentation/widgets/task_edit_sheet.dart`

- [ ] **Step 1: Update TaskEditSheet logic and UI to use TaskController and render the title**
Replace the content of `lib/features/tasks/presentation/widgets/task_edit_sheet.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/app_input.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';

import '../../domain/task_model.dart';
import '../../domain/task_recurrence.dart';
import '../controllers/task_controller.dart';
import 'due_date_picker.dart';
import 'recurrence_picker.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';

class TaskEditSheet extends ConsumerStatefulWidget {
  const TaskEditSheet({
    super.key,
    required this.noteId,
    this.task,
    this.allowTitleEdit = true,
    this.allowDelete = true,
    this.readOnlyTitle = false,
  });

  final String noteId;
  final TaskModel? task;
  final bool allowTitleEdit;
  final bool allowDelete;
  final bool readOnlyTitle;

  static Future<bool?> show(
    BuildContext context, {
    required String noteId,
    TaskModel? task,
    bool allowTitleEdit = true,
    bool allowDelete = true,
    bool readOnlyTitle = false,
  }) {
    return showAppBottomSheet<bool>(
      context: context,
      builder: (_) => TaskEditSheet(
        noteId: noteId,
        task: task,
        allowTitleEdit: allowTitleEdit,
        allowDelete: allowDelete,
        readOnlyTitle: readOnlyTitle,
      ),
    );
  }

  @override
  ConsumerState<TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends ConsumerState<TaskEditSheet> {
  late final TextEditingController _titleController;
  late DateTime? _dueDate;
  late TaskRecurrence? _recurrence;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t?.title ?? '');
    _dueDate = t?.dueDate;
    _recurrence = t?.recurrence;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final title = _titleController.text.trim();
    if (!widget.readOnlyTitle && title.isEmpty) {
      AppMessenger.showInfo('Digite um título para a tarefa.');
      return;
    }

    final controller = ref.read(taskControllerProvider.notifier);
    final navigator = Navigator.of(context);

    if (_isEdit) {
      await controller.updateTask(
        taskId: widget.task!.id,
        title: title,
        dueDate: _dueDate,
        recurrence: _recurrence,
        clearDueDate: _dueDate == null,
        clearRecurrence: _recurrence == null,
      );
    } else {
      await controller.createTask(
        noteId: widget.noteId,
        title: title,
        dueDate: _dueDate,
        recurrence: _recurrence,
      );
    }

    if (ref.read(taskControllerProvider).hasError) {
      if (mounted) AppMessenger.showError('Erro ao salvar tarefa');
      return;
    }
    navigator.pop(true);
  }

  Future<void> _onDelete() async {
    final task = widget.task;
    if (task == null) return;

    final navigator = Navigator.of(context);
    final isRecurrent = task.recurrence != null;
    
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Excluir tarefa',
      message: isRecurrent
          ? 'Tem certeza que deseja excluir esta tarefa recorrente? Ela não será mais reagendada.'
          : 'Tem certeza que deseja excluir esta tarefa?',
      confirmText: 'Excluir',
      isDestructive: true,
    );

    if (confirmed != true) return;

    await ref.read(taskControllerProvider.notifier).deleteTask(task.id);

    if (ref.read(taskControllerProvider).hasError) {
      if (mounted) AppMessenger.showError('Erro ao excluir tarefa');
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(taskControllerProvider).isLoading;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.readOnlyTitle) ...[
            Text('Título', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            AppInput(
              controller: _titleController,
              enabled: widget.allowTitleEdit && !isSaving,
              hintText: 'Digite o título da tarefa',
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(
            'Data de vencimento',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          DueDatePicker(
            initialDate: _dueDate,
            onChanged: (d) => setState(() {
              _dueDate = d;
              if (d == null) _recurrence = null;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Repetição', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          RecurrencePicker(
            initialRecurrence: _recurrence,
            onChanged: (r) => setState(() {
              _recurrence = r;
              if (r != null && _dueDate == null) {
                _dueDate = DateTime.now().startOfDay;
              }
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (_isEdit && widget.allowDelete) ...[
                Expanded(
                  child: AppButton(
                    text: 'Excluir',
                    onPressed: isSaving ? null : _onDelete,
                    variant: AppButtonVariant.danger,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: AppButton(
                  text: 'Cancelar',
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  text: 'Salvar',
                  onPressed: isSaving ? null : _onSave,
                  isLoading: isSaving,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/tasks/presentation/widgets/task_edit_sheet.dart
git commit -m "refactor(tasks): fix title field and integrate TaskController in TaskEditSheet"
```

### Task 4: Delete TaskMetadataSheet and update usages

**Files:**
- Delete: `lib/features/tasks/presentation/widgets/task_metadata_sheet.dart`
- Modify: `lib/features/notes/presentation/inbox_screen.dart`
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`

- [ ] **Step 1: Delete task_metadata_sheet.dart**

```bash
rm lib/features/tasks/presentation/widgets/task_metadata_sheet.dart
```

- [ ] **Step 2: Update inbox_screen.dart**

In `lib/features/notes/presentation/inbox_screen.dart`:
Change the import:
```dart
import '../../tasks/presentation/widgets/task_edit_sheet.dart';
```
(Remove `import '../../tasks/presentation/widgets/task_metadata_sheet.dart';` if present).

Update line 56:
From: `await TaskMetadataSheet.show(context, noteId: task.noteId, task: task);`
To: `await TaskEditSheet.show(context, noteId: task.noteId, task: task, readOnlyTitle: true);`

- [ ] **Step 3: Update note_editor_screen.dart**

In `lib/features/notes/presentation/note_editor_screen.dart`:
Change the import:
```dart
import '../../tasks/presentation/widgets/task_edit_sheet.dart';
```
(Remove `import '../../tasks/presentation/widgets/task_metadata_sheet.dart';` if present).

Update line 46:
From:
```dart
    await TaskMetadataSheet.show(
      context,
      noteId: widget.noteId,
      task: task,
    );
```
To:
```dart
    await TaskEditSheet.show(
      context,
      noteId: widget.noteId,
      task: task,
      readOnlyTitle: true,
      allowDelete: false,
    );
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/notes/presentation/inbox_screen.dart lib/features/notes/presentation/note_editor_screen.dart lib/features/tasks/presentation/widgets/task_metadata_sheet.dart
git commit -m "refactor(tasks): delete TaskMetadataSheet and update usages to TaskEditSheet"
```

### Task 5: Refactor ShareListSection

**Files:**
- Modify: `lib/features/notes/presentation/widgets/share_list_section.dart`

- [ ] **Step 1: Refactor UI and logic in ShareListSection**

Replace content of `lib/features/notes/presentation/widgets/share_list_section.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../domain/share_model.dart';
import '../../domain/share_permission.dart';
import '../controllers/share_list_controller.dart';
import '../controllers/share_note_controller.dart';

class ShareListSection extends ConsumerWidget {
  const ShareListSection({super.key, required this.noteId});

  final String noteId;

  Future<void> _revoke(BuildContext context, WidgetRef ref, ShareModel share) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remover acesso',
      message: 'Tem certeza que deseja remover o acesso deste usuário?',
      confirmText: 'Remover',
      isDestructive: true,
    );
    if (confirmed != true) return;

    await ref.read(shareNoteControllerProvider.notifier).revoke(
      noteId: noteId,
      userId: share.userId,
    );

    if (ref.read(shareNoteControllerProvider).hasError) {
      if (context.mounted) AppMessenger.showError('Erro ao remover acesso');
      return;
    }

    ref.invalidate(shareListProvider(noteId));
    if (context.mounted) AppMessenger.showSuccess('Acesso removido com sucesso');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shareList = ref.watch(shareListProvider(noteId));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pessoas com acesso',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        shareList.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Text(
            error is ApiException ? error.message : error.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          data: (value) => value.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Nenhuma pessoa com acesso',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: value.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final share = value[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(share.email),
                      subtitle: share.name.isNotEmpty ? Text(share.name) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PermissionBadge(permission: share.permission),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            iconSize: 20,
                            onPressed: () => _revoke(context, ref, share),
                            tooltip: 'Remover acesso',
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PermissionBadge extends StatelessWidget {
  const _PermissionBadge({required this.permission});

  final SharePermission permission;

  @override
  Widget build(BuildContext context) {
    final isEdit = permission == SharePermission.edit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isEdit
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isEdit ? 'Editor' : 'Leitor',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/widgets/share_list_section.dart
git commit -m "refactor(shares): use ListView.separated and ShareNoteController in ShareListSection"
```

### Task 6: Refactor ShareNoteSheet

**Files:**
- Modify: `lib/features/notes/presentation/widgets/share_note_sheet.dart`

- [ ] **Step 1: Refactor UI and logic in ShareNoteSheet**

Replace content of `lib/features/notes/presentation/widgets/share_note_sheet.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../shared/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/app_input.dart';
import '../../domain/share_permission.dart';
import '../controllers/share_list_controller.dart';
import '../controllers/share_note_controller.dart';
import 'share_list_section.dart';

class ShareNoteSheet extends ConsumerStatefulWidget {
  final String noteId;

  const ShareNoteSheet({super.key, required this.noteId});

  @override
  ConsumerState<ShareNoteSheet> createState() => _ShareNoteSheetState();
}

class _ShareNoteSheetState extends ConsumerState<ShareNoteSheet> {
  final _emailCtrl = TextEditingController();
  SharePermission _permission = SharePermission.view;
  String? _validationError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _validationError = 'Email inválido');
      return;
    }

    setState(() => _validationError = null);

    await ref.read(shareNoteControllerProvider.notifier).share(
          noteId: widget.noteId,
          email: email,
          permission: _permission,
        );

    final state = ref.read(shareNoteControllerProvider);
    if (!state.hasError && mounted) {
      ref.invalidate(shareListProvider(widget.noteId));
      _emailCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shareState = ref.watch(shareNoteControllerProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Compartilhar Nota',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        AppInput(
          controller: _emailCtrl,
          enabled: !shareState.isLoading,
          keyboardType: TextInputType.emailAddress,
          hintText: 'Email do usuário',
          errorText: _validationError,
        ),
        const SizedBox(height: AppSpacing.md),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Permissão',
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<SharePermission>(
              value: _permission,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: SharePermission.view,
                  child: Text('Leitor'),
                ),
                DropdownMenuItem(
                  value: SharePermission.edit,
                  child: Text('Editor'),
                ),
              ],
              onChanged: shareState.isLoading
                  ? null
                  : (val) => setState(() {
                        if (val != null) _permission = val;
                      }),
            ),
          ),
        ),
        if (shareState.hasError)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              shareState.error is ApiException 
                  ? (shareState.error as ApiException).message 
                  : shareState.error.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: AppButton(
            text: 'Convidar',
            isLoading: shareState.isLoading,
            onPressed: shareState.isLoading ? null : _submit,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Divider(height: 32),
        ShareListSection(noteId: widget.noteId),
      ],
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/notes/presentation/widgets/share_note_sheet.dart
git commit -m "refactor(shares): clean up ShareNoteSheet UI and inputs"
```
