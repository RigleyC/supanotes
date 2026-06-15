import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_tile.dart';

void main() {
  TaskModel buildTask({
    String id = '1',
    String title = 'Buy coffee',
    String status = 'open',
    DateTime? dueDate,
    TaskRecurrence? recurrence,
  }) {
    final now = DateTime(2026, 6, 15);
    return TaskModel(
      id: id,
      userId: 'u',
      noteId: 'n',
      title: title,
      status: status,
      position: 0,
      recurrence: recurrence,
      dueDate: dueDate,
      completedAt: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('TaskTile renders title from TaskModel', (tester) async {
    final task = buildTask(title: 'Buy coffee');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task, onTap: () {}))),
    );

    expect(find.text('Buy coffee'), findsOneWidget);
  });

  testWidgets('TaskTile renders due date via TaskMetadataBadges', (
    tester,
  ) async {
    final task = buildTask(dueDate: DateTime(2026, 6, 15));

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task, onTap: () {}))),
    );

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
  });

  testWidgets('TaskTile renders recurrence label via TaskMetadataBadges', (
    tester,
  ) async {
    final task = buildTask(recurrence: TaskRecurrence.weekly);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task, onTap: () {}))),
    );

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });

  testWidgets('TaskTile hides meta row when no due date or recurrence', (
    tester,
  ) async {
    final task = buildTask();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task, onTap: () {}))),
    );

    expect(find.byIcon(Icons.event_outlined), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });
}
