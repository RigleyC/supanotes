import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/tasks_screen.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_list_tile.dart';

Task _task(String id) {
  final now = DateTime.utc(2026, 9, 15, 10);
  return Task(
    id: id,
    ownerUserId: 'user-1',
    title: id,
    createdAt: now,
    updatedAt: now,
  );
}

GoRouter _router() => GoRouter(
  initialLocation: '/tasks',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) => navigationShell,
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tasks',
              builder: (_, _) => const TasksScreen(),
              routes: [
                GoRoute(
                  path: 'completed',
                  builder: (_, _) => const Scaffold(body: Text('history')),
                ),
                GoRoute(
                  path: 'standalone/:id',
                  builder: (_, state) => Scaffold(
                    body: Text(state.uri.toString()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/notes/:id',
      builder: (_, state) => Scaffold(
        body: Text(state.uri.toString()),
      ),
    ),
  ],
);

Widget _wrap(GoRouter router) {
  final standalone = [TaskListItem.task(_task('standalone'))];
  final withNotes = [
    ...standalone,
    const TaskListItem.note(
      NoteTask(
        noteId: 'note-1',
        blockId: 'block-1',
        title: 'note task',
        noteTitle: 'Minha nota',
      ),
    ),
  ];
  return ProviderScope(
    overrides: [
      taskListProvider(includeNoteTasks: false).overrideWith(
        (ref) => Stream.value(standalone),
      ),
      taskListProvider(includeNoteTasks: true).overrideWith(
        (ref) => Stream.value(withNotes),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('exposes completed history and changes provider input', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Concluídas'), findsOneWidget);
    expect(find.text('note task'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('show-note-tasks-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('note task'), findsOneWidget);
  });

  testWidgets('forwards item taps to source navigation callbacks', (
    tester,
  ) async {
    var standaloneOpened = false;
    var noteOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TaskListTile(
                item: TaskListItem.task(_task('standalone')),
                onTap: () => standaloneOpened = true,
              ),
              TaskListTile(
                item: const TaskListItem.note(
                  NoteTask(
                    noteId: 'note-1',
                    blockId: 'block-1',
                    title: 'note task',
                  ),
                ),
                onTap: () => noteOpened = true,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('standalone'));
    await tester.tap(find.text('note task'));
    expect(standaloneOpened, isTrue);
    expect(noteOpened, isTrue);
  });

  testWidgets('navigates standalone and note tasks with their route identity', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.text('standalone'));
    await tester.pumpAndSettle();
    expect(find.text('/tasks/standalone/standalone'), findsOneWidget);

    router.go('/tasks');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('show-note-tasks-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.text('note task'));
    await tester.pumpAndSettle();
    expect(find.text('/notes/note-1?blockId=block-1'), findsOneWidget);
  });
}
