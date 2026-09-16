import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_history_entry.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/completed_tasks_screen.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/tasks/completed',
  routes: [
    GoRoute(
      path: '/tasks/completed',
      builder: (_, _) => const CompletedTasksScreen(),
    ),
    GoRoute(
      path: '/tasks/standalone/:id',
      builder: (_, state) => Scaffold(
        body: Text(state.uri.toString()),
      ),
    ),
    GoRoute(
      path: '/notes/:id',
      builder: (_, state) => Scaffold(
        body: Text(state.uri.toString()),
      ),
    ),
  ],
);

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

    expect(find.text('Concluída'), findsOneWidget);
    expect(find.textContaining('Concluída em'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-source-filter-menu')),
      findsOneWidget,
    );
  });

  testWidgets('navigates standalone and note history entries', (tester) async {
    final now = DateTime.utc(2026, 9, 15, 10);
    final standalone = Task(
      id: 'standalone-1',
      ownerUserId: 'user-1',
      title: 'Standalone concluída',
      isCompleted: true,
      lastCompletedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    final standaloneEntry = TaskHistoryEntry(
      task: TaskListItem.task(standalone),
      scheduledAt: now,
      completedAt: now,
    );
    final noteEntry = TaskHistoryEntry(
      task: const TaskListItem.note(
        NoteTask(
          noteId: 'note-history',
          blockId: 'block-history',
          title: 'Nota concluída',
        ),
      ),
      scheduledAt: DateTime.utc(2026, 9, 15, 10),
      completedAt: DateTime.utc(2026, 9, 15, 10),
    );
    final router = _router();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          completedTaskHistoryProvider(includeNoteTasks: false).overrideWith(
            (ref) => Stream.value([standaloneEntry]),
          ),
          completedTaskHistoryProvider(includeNoteTasks: true).overrideWith(
            (ref) => Stream.value([standaloneEntry, noteEntry]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final standaloneFinder = find.text('Standalone concluída');
    await tester.ensureVisible(standaloneFinder);
    await tester.tap(standaloneFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/tasks/completed',
    );

    router.go('/tasks/completed');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-source-filter-menu')));
    await tester.pump();
    final option = find.ancestor(
      of: find.text('Mostrar tarefas das notas'),
      matching: find.byType(CupertinoActionSheetAction),
    );
    tester.widget<CupertinoActionSheetAction>(option.first).onPressed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final noteFinder = find.text('Nota concluída');
    await tester.ensureVisible(noteFinder);
    await tester.tap(noteFinder);
    await tester.pumpAndSettle();

    expect(
      find.text('/notes/note-history?blockId=block-history'),
      findsOneWidget,
    );
  });
}
