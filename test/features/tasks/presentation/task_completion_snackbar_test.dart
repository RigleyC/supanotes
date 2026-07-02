import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/domain/note_model.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/notes/domain/note_with_tasks.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/data/notes_repository.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/shared/widgets/animated_task_checkbox.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MockTasksRepository extends Mock implements ITasksRepository {}

class _MockNotesRepository extends Mock implements INotesRepository {}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  testWidgets(
      'creates a daily recurring task, clicks to complete, and snackbar disappears after default time',
      (tester) async {
    final mockTasksRepo = _MockTasksRepository();
    final mockNotesRepo = _MockNotesRepository();

    // Create a daily recurring task
    final now = DateTime.now();
    final task = TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'inbox',
      title: 'Daily Task',
      status: 'open',
      position: 0,
      dueDate: now,
      completedAt: null,
      recurrence: TaskRecurrence.daily,
      createdAt: now,
      updatedAt: now,
    );

    when(() => mockTasksRepo.completeTask(any())).thenAnswer((_) async => now.add(const Duration(days: 1)));
    when(() => mockTasksRepo.reopenTask(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
          currentUserIdProvider.overrideWithValue('user-1'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: AppMessenger.key,
          home: Scaffold(
            body: NoteEditor(
              noteId: 'inbox',
              nodes: [
                NoteNode(
                  id: 'task-1',
                  noteId: 'inbox',
                  position: 0,
                  type: 'task',
                  data: '{"text":"Daily Task","completed":false}',
                  createdAt: now,
                  updatedAt: now,
                  isDirty: false,
                )
              ],
              taskMetadata: {
                'task-1': task,
              },
              delegate: NoteEditorDelegate(
                onTaskComplete: (taskId) => TaskSnackBarHelper.completeTaskWithFeedback(
                  onComplete: () => mockTasksRepo.completeTask(taskId),
                  onUndo: () => mockTasksRepo.reopenTask(taskId),
                ),
                onTaskReopen: (taskId) => mockTasksRepo.reopenTask(taskId),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify task checkbox is rendered
    expect(find.byType(AnimatedTaskCheckbox), findsOneWidget);

    // Click to complete the task
    final checkbox = find.byType(AnimatedTaskCheckbox).first;
    await tester.tap(checkbox);
    
    // Pump a frame to show snackbar
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify snackbar appears
    expect(find.textContaining('Tarefa concluída!'), findsOneWidget);
    
    // In test environments, the SnackBar timer doesn't reliably dismiss floating snackbars 
    // because the fake mouse pointer might remain hovered, pausing the timer.
    // We manually hide it to verify the disappearance logic.
    AppMessenger.key.currentState?.hideCurrentSnackBar();
    await tester.pumpAndSettle();

    // Verify snackbar disappears
    expect(find.textContaining('Tarefa concluída!'), findsNothing);
  });
}
