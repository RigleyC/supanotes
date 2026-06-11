import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  TaskModel task({DateTime? dueDate, String? recurrence}) {
    final now = DateTime.utc(2026, 6, 11);
    return TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Enviar relat\u00f3rio',
      status: 'open',
      position: 0,
      dueDate: dueDate,
      completedAt: null,
      recurrence: recurrence,
      createdAt: now,
      updatedAt: now,
    );
  }

  testWidgets('renders due date and recurrence under inline task text', (
    tester,
  ) async {
    final viewModel = TaskComponentViewModel(
      nodeId: 'task-1',
      padding: EdgeInsets.zero,
      indent: 0,
      isComplete: false,
      setComplete: (_) {},
      text: AttributedText('Enviar relat\u00f3rio'),
      textDirection: TextDirection.ltr,
      textAlignment: TextAlign.left,
      textStyleBuilder: (_) => const TextStyle(fontSize: 16),
      selectionColor: Colors.transparent,
    );

    await tester.pumpWidget(
      wrap(
        CustomTaskComponent(
          viewModel: viewModel,
          taskMetadata: task(dueDate: DateTime.now(), recurrence: 'weekly'),
        ),
      ),
    );

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });
}
