import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MockTasksRepository extends Mock implements ITasksRepository {}

class _MockNotesRepository extends Mock implements INotesRepository {}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  testWidgets(
      'minimal snackbar dismiss test',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Concluída!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.textContaining('Concluída!'), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.textContaining('Concluída!'), findsNothing);
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
      noteId: 'note-1',
      title: 'Daily Task',
      status: 'open',
      position: 0,
      dueDate: now,
      completedAt: null,
      recurrence: TaskRecurrence.daily,
      createdAt: now,
      updatedAt: now,
    );

    when(() => mockTasksRepo.completeTask(any())).thenAnswer((_) async => (nextDue: now.add(const Duration(days: 1)), previousDue: now));
    when(() => mockTasksRepo.reopenTask(any(), originalDueDate: any(named: 'originalDueDate'))).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
          currentUserIdProvider.overrideWithValue('user-1'),
          appDatabaseProvider.overrideWithValue(AppDatabase.test()),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: AppMessenger.key,
          builder: (context, child) => SnackOverlay(child: child!),
          home: Scaffold(
            body: NoteEditor(
              noteId: 'note-1',
              nodes: [
                NoteNode(
                  id: 'task-1',
                  noteId: 'note-1',
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
                  onUndo: (previousDue) => mockTasksRepo.reopenTask(taskId, originalDueDate: previousDue),
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
    expect(find.byType(AppTaskCheckbox), findsOneWidget);

    // Click to complete the task
    final checkbox = find.byType(AppTaskCheckbox).first;
    
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(checkbox));
    await tester.pump();
    await gesture.down(tester.getCenter(checkbox));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // REMOVE pointer to ensure MouseRegion.onExit is triggered!
    await gesture.removePointer();
    await tester.pump();
    
    // Pump a frame to show snackbar
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify snackbar appears
    expect(find.textContaining('Concluída!'), findsOneWidget);
    final snackBarFinder = find.byType(SnackView);
    if (snackBarFinder.evaluate().isNotEmpty) {
      final RenderBox box = tester.renderObject(snackBarFinder);
      final position = box.localToGlobal(Offset.zero);
      final size = box.size;
      print('DEBUG: SnackView position = $position, size = $size');
    }
    
    // Advance time to allow the snackbar to disappear
    await tester.pump(const Duration(seconds: 5));

    // Verify snackbar disappears
    expect(find.textContaining('Concluída!'), findsNothing);
  });
}
