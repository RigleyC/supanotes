import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_actions_sheet.dart';

import 'package:supanotes/features/tasks/domain/task_recurrence.dart';

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

  testWidgets('renders task action controls', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: TaskActionsSheet(task: task())),
        ),
      ),
    );

    expect(find.text('Op\u00e7\u00f5es da tarefa'), findsOneWidget);
    expect(find.text('Comprar caf\u00e9'), findsOneWidget);
    expect(find.text('Data de vencimento'), findsOneWidget);
    expect(find.text('Repeti\u00e7\u00e3o'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });
}
