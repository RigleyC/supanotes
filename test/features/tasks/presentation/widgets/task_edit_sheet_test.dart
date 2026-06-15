import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_edit_sheet.dart';
import 'package:supanotes/shared/widgets/app_input.dart';

void main() {
  TaskModel task() {
    final now = DateTime.utc(2026, 6, 11);
    return TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Comprar caf\u00e9',
      status: 'open',
      position: 0,
      dueDate: now,
      completedAt: null,
      recurrence: TaskRecurrence.daily,
      createdAt: now,
      updatedAt: now,
    );
  }

  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('shows title input when allowTitleEdit is true', (tester) async {
    await tester.pumpWidget(wrap(TaskEditSheet(noteId: 'note-1', task: task())));

    expect(find.byType(AppInput), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('hides title input when allowTitleEdit is false', (tester) async {
    await tester.pumpWidget(
      wrap(TaskEditSheet(
        noteId: 'note-1',
        task: task(),
        allowTitleEdit: false,
      )),
    );

    expect(find.byType(AppInput), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('shows title as text when readOnlyTitle is true and editing', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(TaskEditSheet(
        noteId: 'note-1',
        task: task(),
        allowTitleEdit: false,
        readOnlyTitle: true,
      )),
    );

    expect(find.byType(AppInput), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Comprar caf\u00e9'), findsOneWidget);
  });

  testWidgets('shows delete button when allowDelete is true and editing', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(TaskEditSheet(noteId: 'note-1', task: task())));

    expect(find.text('Excluir'), findsOneWidget);
  });

  testWidgets('hides delete button when allowDelete is false', (tester) async {
    await tester.pumpWidget(
      wrap(TaskEditSheet(
        noteId: 'note-1',
        task: task(),
        allowDelete: false,
      )),
    );

    expect(find.text('Excluir'), findsNothing);
  });

  testWidgets('hides delete button when creating a new task', (tester) async {
    await tester.pumpWidget(wrap(const TaskEditSheet(noteId: 'note-1')));

    expect(find.text('Excluir'), findsNothing);
    expect(find.text('Nova tarefa'), findsOneWidget);
  });
}
