import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_tile.dart';
import 'package:supanotes/shared/widgets/app_task_checkbox.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

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

  testWidgets('renders title from TaskModel', (tester) async {
    final task = buildTask(title: 'Buy coffee');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.text('Buy coffee'), findsOneWidget);
  });

  testWidgets('renders due date badge when dueDate set', (tester) async {
    final task = buildTask(dueDate: DateTime(2026, 6, 15));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
  });

  testWidgets('renders recurrence badge when recurrence set', (tester) async {
    final task = buildTask(recurrence: TaskRecurrence.weekly);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });

  testWidgets('hides meta row when no due date or recurrence', (tester) async {
    final task = buildTask();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    );
    expect(find.byIcon(Icons.event_outlined), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('tap on row toggles completion to true when open',
      (tester) async {
    bool? toggled;
    final task = buildTask(status: 'open');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskTile(
            task: task,
            onToggleComplete: (v) => toggled = v,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buy coffee'));
    await tester.pump();

    expect(toggled, isTrue);
  });

  testWidgets('tap on row toggles completion to false when completed',
      (tester) async {
    bool? toggled;
    final task = buildTask(status: 'done');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskTile(
            task: task,
            onToggleComplete: (v) => toggled = v,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buy coffee'));
    await tester.pump();

    expect(toggled, isFalse);
  });

  testWidgets('long-press on row invokes onOpenMetadata', (tester) async {
    var opened = false;
    final task = buildTask();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskTile(
            task: task,
            onOpenMetadata: () => opened = true,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Buy coffee'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('checkbox is purely visual (no own gesture)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TaskTile(task: buildTask()))),
    );

    expect(
      find.ancestor(
        of: find.byType(AppTaskCheckbox),
        matching: find.byType(GestureDetector),
      ),
      findsOneWidget, // the row-level detector only
    );
  });
}
