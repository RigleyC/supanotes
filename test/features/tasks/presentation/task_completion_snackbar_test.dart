import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/tasks/data/tasks_repository.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_snackbar_helper.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_provider.dart';
import 'package:intl/date_symbol_data_local.dart';

class _MockTasksRepository extends Mock implements ITasksRepository {}

NoteEditorController _createTestController(List<DocumentNode> nodes) {
  final controller = NoteEditorController(userId: 'test-user');
  final doc = MutableDocument(nodes: nodes);
  controller.document = doc;
  controller.bind('note-1');
  controller.composer = MutableDocumentComposer();
  controller.editor = createDefaultDocumentEditor(
    document: doc,
    composer: controller.composer!,
  );
  return controller;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  testWidgets('minimal snackbar dismiss test', (tester) async {
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
    await tester.pump(); // start entry animation
    await tester.pump(
      const Duration(milliseconds: 750),
    ); // let entry animation finish
    expect(find.textContaining('Concluída!'), findsOneWidget);

    await tester.pump(
      const Duration(seconds: 2),
    ); // wait for duration, starts exit animation
    await tester.pump(); // process state change
    await tester.pump(
      const Duration(milliseconds: 750),
    ); // let exit animation finish
    expect(find.textContaining('Concluída!'), findsNothing);
  });

  testWidgets(
    'creates a daily recurring task, clicks to complete, and snackbar disappears after default time',
    (tester) async {
      final mockTasksRepo = _MockTasksRepository();

      // Create a daily recurring task
      final now = DateTime.now();
      final task = TaskModel(
        id: 'task-1',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Daily Task',
        status: 'open',
        position: '0',
        dueDate: now,
        completedAt: null,
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        reminder: null,
        createdAt: now,
        updatedAt: now,
      );

      when(() => mockTasksRepo.completeTask(any())).thenAnswer(
        (_) async => (
          nextDue: now.add(const Duration(days: 1)),
          previousDue: now,
          previousHasTime: false,
        ),
      );
      when(
        () => mockTasksRepo.reopenTask(
          any(),
          originalDueDate: any(named: 'originalDueDate'),
        ),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tasksRepositoryProvider.overrideWithValue(mockTasksRepo),
            currentUserIdProvider.overrideWithValue('user-1'),
            appDatabaseProvider.overrideWithValue(AppDatabase.test()),
            noteEditorControllerProvider.overrideWith((ref, id) async => _createTestController([
              TaskNode(id: 'task-1', text: AttributedText('Tarefa recorrente'), isComplete: false),
            ])),
          ],
          child: MaterialApp(
            scaffoldMessengerKey: AppMessenger.key,
            builder: (context, child) => SnackOverlay(child: child!),
            home: Scaffold(
              body: NoteEditor(
                noteId: 'note-1',
                taskMetadata: {'task-1': task},
                delegate: NoteEditorDelegate(
                  onTaskComplete: (taskId) =>
                      TaskSnackBarHelper.completeTaskWithFeedback(
                        onComplete: () async => (
                          nextDue: task.dueDate,
                          previousDue: task.dueDate,
                          previousHasTime: task.hasTime,
                          scheduledAt: task.dueDate,
                        ),
                        onUndo: (previousDue, _, _) => mockTasksRepo
                            .reopenTask(taskId, originalDueDate: previousDue),
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
        // SnackView rendered successfully
      }

      // Advance time to allow the snackbar to disappear
      await tester.pump(const Duration(seconds: 5));

      // Verify snackbar disappears
      expect(find.textContaining('Concluída!'), findsNothing);
    },
  );
}
