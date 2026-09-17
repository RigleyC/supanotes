import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
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
      standaloneTaskProvider('standalone').overrideWith(
        (ref) => Stream.value(_task('standalone')),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _showNoteTasks(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('task-source-filter-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mostrar tarefas das notas'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  testWidgets('exposes completed history and changes provider input', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('note task'), findsNothing);
    await _showNoteTasks(tester);
    expect(find.text('note task'), findsOneWidget);
  });

  testWidgets('opens the create sheet without pushing the standalone route', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/tasks');
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

  testWidgets('uses the checkbox region to complete a standalone task', (
    tester,
  ) async {
    var toggled = false;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListTile(
            item: TaskListItem.task(_task('standalone')),
            onTap: () => opened = true,
            onToggle: () async => toggled = true,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('task-toggle-standalone:standalone')),
    );
    expect(toggled, isTrue);
    expect(opened, isFalse);

    await tester.tap(find.text('standalone'));
    expect(opened, isTrue);
  });

  testWidgets('opens standalone tasks in a modal and keeps note deep links', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.text('standalone'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/tasks');

    router.go('/tasks');
    await tester.pumpAndSettle();
    await _showNoteTasks(tester);

    final noteFinder = find.text('note task');
    await tester.ensureVisible(noteFinder);
    await tester.tap(noteFinder);
    await tester.pumpAndSettle();
    expect(find.text('/notes/note-1?blockId=block-1'), findsOneWidget);
  });
}
