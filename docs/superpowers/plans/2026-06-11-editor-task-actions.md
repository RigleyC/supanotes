# Editor Task Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show due-date and recurrence metadata under inline checklist items in the `super_editor` note editor, then let users long-press a checklist item to edit those task options in a bottom sheet.

**Architecture:** Keep `super_editor`'s `TaskNode` as the document anchor for text/check state only. Read and mutate task metadata (`dueDate`, `recurrence`, status, delete) through the existing `tasks` repository because those fields already live in Drift/backend task rows. The editor screen passes a `Map<taskId, TaskModel>` into the custom task component, and the component renders metadata badges plus exposes a long-press callback.

**Tech Stack:** Flutter, Riverpod manual providers, Drift, `super_editor`, existing `TaskModel`, `tasksByNoteStreamProvider`, `DueDatePicker`, `RecurrencePicker`, and `showAppBottomSheet`.

---

## Scope

This plan covers inline checklist items inside:

- `lib/features/notes/presentation/note_editor_screen.dart`
- `lib/features/notes/presentation/inbox_screen.dart`

The plan does not add new recurrence rules, reminders with time-of-day, priority, tags, or custom schedules. Existing supported recurrence values remain:

- `daily`
- `weekdays`
- `weekly`
- `monthly`

## File Structure

- Modify `lib/features/notes/presentation/widgets/custom_task_component.dart`
  - Accept task metadata and long-press callback.
  - Render metadata badges under checklist item text.
  - Preserve `ProxyTextComposable` behavior by keeping `_textKey` on the `TextComponent`.

- Create `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
  - Small reusable presentation widget for due-date and recurrence badges.
  - Owns labels/icons/colors for metadata display.

- Create `lib/features/tasks/presentation/widgets/task_actions_sheet.dart`
  - Bottom sheet for quick task actions from inline editor tasks.
  - Reuses `DueDatePicker` and `RecurrencePicker`.
  - Does not edit the title; title stays owned by the editor text.

- Modify `lib/features/notes/presentation/note_editor_screen.dart`
  - Watch `tasksByNoteStreamProvider(noteId)`.
  - Pass metadata map and long-press handler into `CustomTaskComponentBuilder`.

- Modify `lib/features/notes/presentation/inbox_screen.dart`
  - Watch `tasksByNoteStreamProvider(inbox.id)` after inbox is available.
  - Pass metadata map and long-press handler into `CustomTaskComponentBuilder`.

- Modify `lib/features/notes/presentation/controllers/note_editor_controller.dart`
  - Add a snapshot flush method that saves current document/task rows without applying empty-note deletion.
  - Use this before opening the actions sheet so a newly typed checklist item exists in `tasks`.

- Test `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart`
  - Widget tests for due-date and recurrence badges.

- Test `test/features/tasks/presentation/widgets/task_actions_sheet_test.dart`
  - Widget tests for sheet rendering and save behavior with a fake repository.

- Test `test/features/notes/presentation/widgets/custom_task_component_test.dart`
  - Widget test for metadata rendering and long-press callback on the custom component.

---

## Task 1: Add Task Metadata Badges Widget

**Files:**
- Create: `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`
- Test: `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/tasks/presentation/widgets/task_metadata_badges_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('shows no badges when due date and recurrence are absent', (tester) async {
    await tester.pumpWidget(wrap(const TaskMetadataBadges()));

    expect(find.byIcon(Icons.event_outlined), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('shows Hoje for today due date', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await tester.pumpWidget(wrap(TaskMetadataBadges(dueDate: today)));

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.text('Hoje'), findsOneWidget);
  });

  testWidgets('shows recurrence label', (tester) async {
    await tester.pumpWidget(wrap(const TaskMetadataBadges(recurrence: 'weekly')));

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart
```

Expected: FAIL because `task_metadata_badges.dart` does not exist.

- [ ] **Step 3: Create the widget**

Create `lib/features/tasks/presentation/widgets/task_metadata_badges.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

import 'recurrence_picker.dart';

class TaskMetadataBadges extends StatelessWidget {
  const TaskMetadataBadges({
    super.key,
    this.dueDate,
    this.recurrence,
  });

  final DateTime? dueDate;
  final String? recurrence;

  bool get _hasRecurrence => recurrence != null && recurrence!.isNotEmpty;
  bool get _hasDueDate => dueDate != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasDueDate && !_hasRecurrence) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_hasDueDate)
          _MetadataPill(
            icon: Icons.event_outlined,
            label: _dueDateLabel(dueDate!),
            color: _dueDateColor(context, dueDate!),
          ),
        if (_hasRecurrence)
          _MetadataPill(
            icon: Icons.refresh,
            label: recurrenceLabel(recurrence),
            color: scheme.onSurfaceVariant,
          ),
      ],
    );
  }

  String _dueDateLabel(DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dueDate.year, dueDate.month, dueDate.day);

    if (date == today) return 'Hoje';
    if (date.isBefore(today)) {
      return 'Atrasada · ${DateFormat('d MMM').format(dueDate)}';
    }
    return DateFormat('d MMM').format(dueDate);
  }

  Color _dueDateColor(BuildContext context, DateTime dueDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dueDate.year, dueDate.month, dueDate.day);
    if (date.isBefore(today)) return Theme.of(context).colorScheme.error;
    if (date == today) return AppColors.success;
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
}

class _MetadataPill extends StatelessWidget {
  const _MetadataPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
              ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run:

```bash
flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart
```

Expected: PASS.

- [ ] **Step 5: Format and commit**

Run:

```bash
dart format lib/features/tasks/presentation/widgets/task_metadata_badges.dart test/features/tasks/presentation/widgets/task_metadata_badges_test.dart
flutter analyze lib/features/tasks/presentation/widgets/task_metadata_badges.dart test/features/tasks/presentation/widgets/task_metadata_badges_test.dart
git add lib/features/tasks/presentation/widgets/task_metadata_badges.dart test/features/tasks/presentation/widgets/task_metadata_badges_test.dart
git commit -m "feat(tasks): add task metadata badges"
```

Expected: formatter completes, analyze reports no issues, commit succeeds.

---

## Task 2: Render Metadata Under Inline Editor Tasks

**Files:**
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart`
- Test: `test/features/notes/presentation/widgets/custom_task_component_test.dart`

- [ ] **Step 1: Write a focused widget test for metadata rendering**

Create `test/features/notes/presentation/widgets/custom_task_component_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  TaskModel task({
    DateTime? dueDate,
    String? recurrence,
  }) {
    final now = DateTime.utc(2026, 6, 11);
    return TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Enviar relatório',
      status: 'open',
      position: 0,
      dueDate: dueDate,
      completedAt: null,
      recurrence: recurrence,
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('renders due date and recurrence under inline task text', (tester) async {
    final viewModel = TaskComponentViewModel(
      nodeId: 'task-1',
      padding: EdgeInsets.zero,
      indent: 0,
      isComplete: false,
      setComplete: (_) {},
      text: AttributedText('Enviar relatório'),
      textDirection: TextDirection.ltr,
      textAlignment: TextAlign.left,
      textStyleBuilder: (_) => const TextStyle(fontSize: 16),
      selectionColor: Colors.transparent,
    );

    await tester.pumpWidget(
      wrap(
        CustomTaskComponent(
          viewModel: viewModel,
          taskMetadata: task(
            dueDate: DateTime.now(),
            recurrence: 'weekly',
          ),
        ),
      ),
    );

    expect(find.text('Enviar relatório'), findsOneWidget);
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
flutter test test/features/notes/presentation/widgets/custom_task_component_test.dart
```

Expected: FAIL because `CustomTaskComponent` does not accept `taskMetadata`.

- [ ] **Step 3: Update `CustomTaskComponentBuilder` and `CustomTaskComponent`**

Modify `lib/features/notes/presentation/widgets/custom_task_component.dart`.

Add imports:

```dart
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';
```

Change the builder constructor and fields:

```dart
class CustomTaskComponentBuilder implements ComponentBuilder {
  CustomTaskComponentBuilder(
    this._editor, {
    this.taskMetadataById = const {},
    this.onTaskLongPress,
  });

  final Editor _editor;
  final Map<String, TaskModel> taskMetadataById;
  final ValueChanged<String>? onTaskLongPress;
```

Change `createComponent`:

```dart
    return CustomTaskComponent(
      key: componentContext.componentKey,
      viewModel: componentViewModel,
      taskMetadata: taskMetadataById[componentViewModel.nodeId],
      onLongPress: onTaskLongPress == null
          ? null
          : () => onTaskLongPress!(componentViewModel.nodeId),
    );
```

Change `CustomTaskComponent` constructor:

```dart
class CustomTaskComponent extends StatefulWidget {
  const CustomTaskComponent({
    super.key,
    required this.viewModel,
    this.taskMetadata,
    this.onLongPress,
  });

  final TaskComponentViewModel viewModel;
  final TaskModel? taskMetadata;
  final VoidCallback? onLongPress;
```

Replace the `Expanded` child in `build()` with:

```dart
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: widget.onLongPress,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextComponent(
                      key: _textKey,
                      text: widget.viewModel.text,
                      textDirection: widget.viewModel.textDirection,
                      textAlign: widget.viewModel.textAlignment,
                      maxLines: widget.viewModel.maxLines,
                      overflow: widget.viewModel.overflow,
                      textStyleBuilder: _computeStyles,
                      inlineWidgetBuilders: widget.viewModel.inlineWidgetBuilders,
                      textSelection: widget.viewModel.selection,
                      selectionColor: widget.viewModel.selectionColor,
                      highlightWhenEmpty: widget.viewModel.highlightWhenEmpty,
                      underlines: widget.viewModel.createUnderlines(),
                    ),
                    if (widget.taskMetadata?.dueDate != null ||
                        (widget.taskMetadata?.recurrence != null &&
                            widget.taskMetadata!.recurrence!.isNotEmpty)) ...[
                      const SizedBox(height: 4),
                      TaskMetadataBadges(
                        dueDate: widget.taskMetadata?.dueDate,
                        recurrence: widget.taskMetadata?.recurrence,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
```

- [ ] **Step 4: Run the component test**

Run:

```bash
flutter test test/features/notes/presentation/widgets/custom_task_component_test.dart
```

Expected: PASS.

- [ ] **Step 5: Format, analyze, and commit**

Run:

```bash
dart format lib/features/notes/presentation/widgets/custom_task_component.dart test/features/notes/presentation/widgets/custom_task_component_test.dart
flutter analyze lib/features/notes/presentation/widgets/custom_task_component.dart test/features/notes/presentation/widgets/custom_task_component_test.dart
git add lib/features/notes/presentation/widgets/custom_task_component.dart test/features/notes/presentation/widgets/custom_task_component_test.dart
git commit -m "feat(notes): show task metadata in editor"
```

Expected: no analyzer issues, commit succeeds.

---

## Task 3: Wire Task Metadata Into Note Editor Screens

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
- Modify: `lib/features/notes/presentation/inbox_screen.dart`

- [ ] **Step 1: Modify `note_editor_screen.dart` imports**

Add:

```dart
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
```

- [ ] **Step 2: Add a helper to map task rows by ID**

Inside `_NoteEditorScreenState`, add:

```dart
Map<String, TaskModel> _taskMapForNote(String noteId) {
  return ref.watch(tasksByNoteStreamProvider(noteId)).maybeWhen(
        data: (tasks) => {for (final task in tasks) task.id: task},
        orElse: () => const <String, TaskModel>{},
      );
}
```

- [ ] **Step 3: Pass metadata into the editor component builder**

In `build()`, after the controller is known and before returning `PopScope`, add:

```dart
    final taskMetadataById = _taskMapForNote(widget.noteId);
```

Then change the builder:

```dart
                CustomTaskComponentBuilder(
                  controller.editor!,
                  taskMetadataById: taskMetadataById,
                ),
```

- [ ] **Step 4: Modify `inbox_screen.dart` imports**

Add:

```dart
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
```

- [ ] **Step 5: Add an inbox task metadata helper**

Inside `_InboxScreenState`, add:

```dart
Map<String, TaskModel> _taskMapForInbox(String? noteId) {
  if (noteId == null) return const <String, TaskModel>{};
  return ref.watch(tasksByNoteStreamProvider(noteId)).maybeWhen(
        data: (tasks) => {for (final task in tasks) task.id: task},
        orElse: () => const <String, TaskModel>{},
      );
}
```

- [ ] **Step 6: Pass inbox metadata into the builder**

In `InboxScreen.build`, derive `inboxId` from the async value:

```dart
    final inboxId = asyncValue.asData?.value?.id;
    final taskMetadataById = _taskMapForInbox(inboxId);
```

Then change the builder:

```dart
                  CustomTaskComponentBuilder(
                    controller.editor!,
                    taskMetadataById: taskMetadataById,
                  ),
```

- [ ] **Step 7: Analyze both screens**

Run:

```bash
flutter analyze lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart
```

Expected: no issues.

- [ ] **Step 8: Commit**

Run:

```bash
git add lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart
git commit -m "feat(notes): wire task metadata into editors"
```

Expected: commit succeeds.

---

## Task 4: Add Snapshot Flush for Task Actions

**Files:**
- Modify: `lib/features/notes/presentation/controllers/note_editor_controller.dart`
- Test: add or update the nearest controller test if one exists. If no controller test exists, verify with analyze and manual behavior in Task 6.

- [ ] **Step 1: Add a public save method**

In `NoteEditorController`, add this method after `_runSnapshotSave()`:

```dart
  Future<void> persistSnapshotNow() async {
    final noteId = _noteId;
    final doc = document;
    if (noteId == null || doc == null) return;

    final generation = _saveThrottle.nextGeneration();
    await _saveThrottle.flush(
      generation: generation,
      operation: _runSnapshotSave,
    );
  }
```

This method intentionally does not call `emptyNoteExit`. It only forces the current document and extracted task list into `notesRepository.saveNoteSnapshot`, which in turn calls `syncTasksFromDocument`.

- [ ] **Step 2: Analyze the controller**

Run:

```bash
flutter analyze lib/features/notes/presentation/controllers/note_editor_controller.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

Run:

```bash
git add lib/features/notes/presentation/controllers/note_editor_controller.dart
git commit -m "feat(notes): expose editor snapshot flush"
```

Expected: commit succeeds.

---

## Task 5: Add Task Actions Bottom Sheet

**Files:**
- Create: `lib/features/tasks/presentation/widgets/task_actions_sheet.dart`
- Test: `test/features/tasks/presentation/widgets/task_actions_sheet_test.dart`

- [ ] **Step 1: Write the sheet widget**

Create `lib/features/tasks/presentation/widgets/task_actions_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/due_date_picker.dart';
import 'package:supanotes/features/tasks/presentation/widgets/recurrence_picker.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_button.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';

class TaskActionsSheet extends ConsumerStatefulWidget {
  const TaskActionsSheet({
    super.key,
    required this.task,
  });

  final TaskModel task;

  static Future<void> show(
    BuildContext context, {
    required TaskModel task,
  }) {
    return showAppBottomSheet<void>(
      context: context,
      builder: (_) => TaskActionsSheet(task: task),
    );
  }

  @override
  ConsumerState<TaskActionsSheet> createState() => _TaskActionsSheetState();
}

class _TaskActionsSheetState extends ConsumerState<TaskActionsSheet> {
  late DateTime? _dueDate;
  late String? _recurrence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.task.dueDate;
    _recurrence = widget.task.recurrence;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      await ref.read(tasksRepositoryProvider).updateTask(
            widget.task.id,
            dueDate: _dueDate,
            recurrence: _recurrence,
            clearDueDate: _dueDate == null,
            clearRecurrence: _recurrence == null || _recurrence!.isEmpty,
          );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, 'Erro ao salvar tarefa: $e');
      setState(() => _saving = false);
    }
  }

  Future<void> _toggleComplete() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      final repo = ref.read(tasksRepositoryProvider);
      if (widget.task.isCompleted) {
        await repo.reopenTask(widget.task.id);
      } else {
        await repo.completeTask(widget.task.id);
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      AppMessenger.showError(context, 'Erro ao atualizar tarefa: $e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Opções da tarefa',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Data de vencimento', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          DueDatePicker(
            initialDate: _dueDate,
            onChanged: (date) => setState(() => _dueDate = date),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Repetição', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          RecurrencePicker(
            initialRecurrence: _recurrence,
            onChanged: (value) => setState(() => _recurrence = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              IntrinsicWidth(
                child: AppButton(
                  text: widget.task.isCompleted ? 'Reabrir' : 'Concluir',
                  variant: AppButtonVariant.secondary,
                  onPressed: _saving ? null : _toggleComplete,
                ),
              ),
              const Spacer(),
              IntrinsicWidth(
                child: AppButton(
                  text: 'Cancelar',
                  variant: AppButtonVariant.secondary,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IntrinsicWidth(
                child: AppButton(
                  text: 'Salvar',
                  isLoading: _saving,
                  onPressed: _saving ? null : _save,
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

- [ ] **Step 2: Write a basic rendering test**

Create `test/features/tasks/presentation/widgets/task_actions_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_actions_sheet.dart';

void main() {
  TaskModel task() {
    final now = DateTime.utc(2026, 6, 11);
    return TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Comprar café',
      status: 'open',
      position: 0,
      dueDate: now,
      completedAt: null,
      recurrence: 'daily',
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('renders task action controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskActionsSheet(task: task()),
        ),
      ),
    );

    expect(find.text('Opções da tarefa'), findsOneWidget);
    expect(find.text('Comprar café'), findsOneWidget);
    expect(find.text('Data de vencimento'), findsOneWidget);
    expect(find.text('Repetição'), findsOneWidget);
    expect(find.text('Concluir'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run the sheet test**

Run:

```bash
flutter test test/features/tasks/presentation/widgets/task_actions_sheet_test.dart
```

Expected: PASS.

- [ ] **Step 4: Format, analyze, and commit**

Run:

```bash
dart format lib/features/tasks/presentation/widgets/task_actions_sheet.dart test/features/tasks/presentation/widgets/task_actions_sheet_test.dart
flutter analyze lib/features/tasks/presentation/widgets/task_actions_sheet.dart test/features/tasks/presentation/widgets/task_actions_sheet_test.dart
git add lib/features/tasks/presentation/widgets/task_actions_sheet.dart test/features/tasks/presentation/widgets/task_actions_sheet_test.dart
git commit -m "feat(tasks): add inline task actions sheet"
```

Expected: no analyzer issues, commit succeeds.

---

## Task 6: Wire Long Press to Task Actions Sheet

**Files:**
- Modify: `lib/features/notes/presentation/note_editor_screen.dart`
- Modify: `lib/features/notes/presentation/inbox_screen.dart`
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart` if Task 2 did not already add `onTaskLongPress`.

- [ ] **Step 1: Import the sheet in `note_editor_screen.dart`**

Add:

```dart
import 'package:supanotes/features/tasks/presentation/widgets/task_actions_sheet.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
```

- [ ] **Step 2: Add the note editor long-press handler**

Inside `_NoteEditorScreenState`, add:

```dart
Future<void> _openTaskActions(
  NoteEditorController controller,
  Map<String, TaskModel> taskMetadataById,
  String taskId,
) async {
  await controller.persistSnapshotNow();
  if (!mounted) return;

  final task = taskMetadataById[taskId];
  if (task == null) {
    AppMessenger.showInfo(
      context,
      'A tarefa acabou de ser criada. Tente novamente em instantes.',
    );
    return;
  }

  await TaskActionsSheet.show(context, task: task);
}
```

- [ ] **Step 3: Pass the callback into `CustomTaskComponentBuilder`**

Change the builder in `note_editor_screen.dart`:

```dart
                CustomTaskComponentBuilder(
                  controller.editor!,
                  taskMetadataById: taskMetadataById,
                  onTaskLongPress: (taskId) =>
                      _openTaskActions(controller, taskMetadataById, taskId),
                ),
```

- [ ] **Step 4: Wire inbox long press**

In `inbox_screen.dart`, import:

```dart
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_actions_sheet.dart';
```

Add the same handler shape inside `_InboxScreenState`:

```dart
Future<void> _openTaskActions(
  NoteEditorController controller,
  Map<String, TaskModel> taskMetadataById,
  String taskId,
) async {
  await controller.persistSnapshotNow();
  if (!mounted) return;

  final task = taskMetadataById[taskId];
  if (task == null) {
    AppMessenger.showInfo(
      context,
      'A tarefa acabou de ser criada. Tente novamente em instantes.',
    );
    return;
  }

  await TaskActionsSheet.show(context, task: task);
}
```

Then pass it to the inbox builder:

```dart
                  CustomTaskComponentBuilder(
                    controller.editor!,
                    taskMetadataById: taskMetadataById,
                    onTaskLongPress: (taskId) =>
                        _openTaskActions(controller, taskMetadataById, taskId),
                  ),
```

- [ ] **Step 5: Analyze changed files**

Run:

```bash
flutter analyze lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart lib/features/notes/presentation/widgets/custom_task_component.dart
```

Expected: no issues.

- [ ] **Step 6: Manual runtime check**

Run the app on Android or desktop:

```bash
flutter run
```

Manual expected behavior:

- Open a note with checklist items.
- A task with no due date and no recurrence shows no metadata line.
- Set recurrence/date through an existing task UI, then reopen the note.
- The inline checklist item shows the due-date icon/label and recurrence icon/label.
- Long-press the inline checklist item.
- The bottom sheet opens with date and recurrence controls.
- Changing recurrence/date and tapping `Salvar` updates the badges after the sheet closes.

- [ ] **Step 7: Commit**

Run:

```bash
git add lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart lib/features/notes/presentation/widgets/custom_task_component.dart
git commit -m "feat(notes): open task actions from editor"
```

Expected: commit succeeds.

---

## Task 7: Guard Against Editor/Task Drift

**Files:**
- Modify: `lib/features/tasks/presentation/widgets/task_actions_sheet.dart`
- Modify: `lib/features/notes/presentation/widgets/custom_task_component.dart`

- [ ] **Step 1: Keep title editing out of the actions sheet**

Confirm `TaskActionsSheet` has no editable title input. This is intentional because the title source of truth inside the editor is the `TaskNode.text`. Editing the title in the sheet would be overwritten by the next editor autosave.

The sheet may show the title as read-only:

```dart
          Text(
            widget.task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
```

- [ ] **Step 2: Do not write recurrence into node metadata**

Confirm `custom_task_component.dart` only reads `TaskModel? taskMetadata` and never mutates `node.metadata`.

Allowed:

```dart
TaskMetadataBadges(
  dueDate: widget.taskMetadata?.dueDate,
  recurrence: widget.taskMetadata?.recurrence,
)
```

Not allowed:

```dart
node.metadata['recurrence'] = recurrence;
```

- [ ] **Step 3: Run a targeted search**

Run:

```bash
rg -n "metadata\\['recurrence'\\]|metadata\\['dueDate'\\]|metadata\\[\"recurrence\"\\]|metadata\\[\"dueDate\"\\]" lib
```

Expected: no matches.

- [ ] **Step 4: Run full targeted tests**

Run:

```bash
flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart test/features/tasks/presentation/widgets/task_actions_sheet_test.dart test/features/notes/presentation/widgets/custom_task_component_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit any guard fixes**

If Task 7 changed files, run:

```bash
git add lib/features/tasks/presentation/widgets/task_actions_sheet.dart lib/features/notes/presentation/widgets/custom_task_component.dart
git commit -m "test(tasks): guard inline task metadata ownership"
```

Expected: commit succeeds if changes exist. If no files changed, do not create an empty commit.

---

## Final Verification

- [ ] **Step 1: Run formatting**

```bash
dart format lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart lib/features/tasks/presentation/widgets/task_metadata_badges.dart lib/features/tasks/presentation/widgets/task_actions_sheet.dart test/features/tasks/presentation/widgets/task_metadata_badges_test.dart test/features/tasks/presentation/widgets/task_actions_sheet_test.dart test/features/notes/presentation/widgets/custom_task_component_test.dart
```

Expected: formatter completes.

- [ ] **Step 2: Run targeted analysis**

```bash
flutter analyze lib/features/notes/presentation/widgets/custom_task_component.dart lib/features/notes/presentation/note_editor_screen.dart lib/features/notes/presentation/inbox_screen.dart lib/features/tasks/presentation/widgets/task_metadata_badges.dart lib/features/tasks/presentation/widgets/task_actions_sheet.dart
```

Expected: no issues.

- [ ] **Step 3: Run targeted tests**

```bash
flutter test test/features/tasks/presentation/widgets/task_metadata_badges_test.dart test/features/tasks/presentation/widgets/task_actions_sheet_test.dart test/features/notes/presentation/widgets/custom_task_component_test.dart
```

Expected: all tests pass.

- [ ] **Step 4: Manual smoke test**

```bash
flutter run
```

Expected:

- Inline checklist item without metadata remains visually unchanged.
- Inline checklist item with `dueDate` shows an event icon and date label below the text.
- Inline checklist item with `recurrence` shows a refresh icon and recurrence label below the text.
- Long-press opens the task options sheet.
- Saving the sheet updates task badges without editing the checklist text.

---

## Self-Review

**Spec coverage:** The plan covers metadata display, due date, recurrence, long-press access, bottom sheet controls, and data ownership between `TaskNode` and persisted `tasks`.

**Placeholder scan:** No task uses placeholder instructions. Every code step includes concrete snippets and commands.

**Type consistency:** The plan consistently uses `TaskModel`, `tasksByNoteStreamProvider`, `CustomTaskComponentBuilder`, `TaskMetadataBadges`, and `TaskActionsSheet`.
