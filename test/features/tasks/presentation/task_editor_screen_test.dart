import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/presentation/task_editor_screen.dart';

void main() {
  testWidgets('recovers a standalone task after retrying the provider', (
    tester,
  ) async {
    var attempts = 0;
    final task = Task(
      id: 'task-1',
      ownerUserId: 'user-1',
      title: 'Task recuperada',
      createdAt: DateTime.utc(2026, 9, 15),
      updatedAt: DateTime.utc(2026, 9, 15),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          standaloneTaskProvider('task-1').overrideWith((ref) {
            attempts++;
            return attempts == 1
                ? Stream<Task?>.error(StateError('offline'))
                : Stream.value(task);
          }),
        ],
        child: const MaterialApp(
          home: TaskEditorScreen(taskId: 'task-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Erro ao carregar a task'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Task recuperada'), findsOneWidget);
    expect(attempts, 2);
  });
}
