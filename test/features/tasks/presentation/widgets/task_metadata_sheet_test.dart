import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';

void main() {
  TaskModel task() {
    final now = DateTime.utc(2026, 6, 11);
    return TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Comprar cafe',
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
  testWidgets('renders metadata pickers for existing task', (tester) async {
    await tester.pumpWidget(wrap(TaskMetadataSheet(noteId: 'note-1', task: task())));
    await tester.pumpAndSettle();

    expect(find.text('Data de vencimento'), findsOneWidget);
    expect(find.text('Repetição'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
  });

  testWidgets('does not show title input', (tester) async {
    await tester.pumpWidget(wrap(TaskMetadataSheet(noteId: 'note-1', task: task())));

    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('does not show delete button', (tester) async {
    await tester.pumpWidget(wrap(TaskMetadataSheet(noteId: 'note-1', task: task())));

    expect(find.text('Excluir'), findsNothing);
  });
}
