import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_history_entry.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/completed_tasks_screen.dart';

void main() {
  testWidgets('renders completion history from the provider', (tester) async {
    final now = DateTime.utc(2026, 9, 15, 10);
    final task = Task(
      id: 'task-1',
      ownerUserId: 'user-1',
      title: 'Concluída',
      isCompleted: true,
      lastCompletedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final entry = TaskHistoryEntry(
      task: TaskListItem.task(task),
      scheduledAt: now,
      completedAt: now,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedTaskHistoryProvider(includeNoteTasks: false).overrideWith(
            (ref) => Stream.value([entry]),
          ),
          completedTaskHistoryProvider(includeNoteTasks: true).overrideWith(
            (ref) => Stream.value([entry]),
          ),
        ],
        child: const MaterialApp(home: CompletedTasksScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Concluídas'), findsAtLeastNWidgets(1));
    expect(find.text('Concluída'), findsOneWidget);
    expect(find.textContaining('Concluída em'), findsOneWidget);
  });
}
