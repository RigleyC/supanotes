import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/core/router/app_router.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/application/task_list_providers.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/domain/task_list_item.dart';
import 'package:supanotes/features/tasks/presentation/tasks_screen.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_list_tile.dart';
import 'package:supanotes/shared/widgets/app_navigation_shell.dart';

Task _task(String id, {DateTime? dueDate, bool hasTime = false}) {
  final now = DateTime.utc(2026, 9, 15, 10);
  return Task(
    id: id,
    ownerUserId: 'user-1',
    title: id,
    dueDate: dueDate,
    hasTime: hasTime,
    createdAt: now,
    updatedAt: now,
  );
}

GoRouter _router() => GoRouter(
  initialLocation: '/tasks',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) => AppNavigationShell(
        navigationShell: navigationShell,
        destinations: [appNavigationDestinations.first],
      ),
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

Widget _wrap(GoRouter router, {List<TaskListItem>? standaloneItems}) {
  final standalone =
      standaloneItems ?? [TaskListItem.task(_task('standalone'))];
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

Future<void> _toggleNoteTasks(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('task-source-filter-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('shows note tasks by default and can hide them', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('note task'), findsOneWidget);
    await _toggleNoteTasks(tester, 'Ocultar tarefas das notas');
    expect(find.text('note task'), findsNothing);
    expect(find.text('standalone'), findsOneWidget);
  });

  testWidgets('groups open tasks into overdue, today and later sections', (
    tester,
  ) async {
    final now = DateTime.now();
    DateTime day(int offset) => DateTime(now.year, now.month, now.day + offset);
    final router = _router();
    await tester.pumpWidget(
      _wrap(
        router,
        standaloneItems: [
          TaskListItem.task(_task('overdue', dueDate: day(-3))),
          TaskListItem.task(_task('today', dueDate: day(0))),
          TaskListItem.task(_task('tomorrow', dueDate: day(1))),
          TaskListItem.task(_task('undated')),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final overdueHeader = find.byKey(const ValueKey('task-section-overdue'));
    final todayHeader = find.byKey(const ValueKey('task-section-today'));
    final laterHeader = find.byKey(const ValueKey('task-section-later'));
    expect(find.text('Atrasada'), findsOneWidget);
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Depois'), findsOneWidget);
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(overdueHeader), lessThan(top(find.text('overdue'))));
    expect(top(find.text('overdue')), lessThan(top(todayHeader)));
    expect(top(todayHeader), lessThan(top(find.text('today'))));
    expect(top(find.text('today')), lessThan(top(laterHeader)));
    expect(top(laterHeader), lessThan(top(find.text('tomorrow'))));
    expect(top(find.text('tomorrow')), lessThan(top(find.text('undated'))));

    expect(find.text('amanhã'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('task-trailing-standalone:today')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('task-trailing-standalone:undated')),
      findsNothing,
    );
    final overdueLabel = tester.widget<Text>(
      find.byKey(const ValueKey('task-trailing-standalone:overdue')),
    );
    final scheme = Theme.of(tester.element(overdueHeader)).colorScheme;
    expect(overdueLabel.style?.color, scheme.error);
  });

  testWidgets('omits empty sections', (tester) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Depois'), findsOneWidget);
    expect(find.text('Atrasada'), findsNothing);
    expect(find.text('Hoje'), findsNothing);
  });

  testWidgets('opens completed history from the end-of-list link', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.byKey(const ValueKey('completed-tasks-entry')));
    await tester.pumpAndSettle();
    expect(find.text('history'), findsOneWidget);
  });

  testWidgets('shows the empty state above the completed link', (
    tester,
  ) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router, standaloneItems: const []));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await _toggleNoteTasks(tester, 'Ocultar tarefas das notas');

    expect(find.text('Tudo em dia'), findsOneWidget);
    expect(find.byKey(const ValueKey('completed-tasks-entry')), findsOneWidget);
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

    final noteFinder = find.text('note task');
    await tester.ensureVisible(noteFinder);
    await tester.tap(noteFinder);
    await tester.pumpAndSettle();
    expect(find.text('/notes/note-1?blockId=block-1'), findsOneWidget);
  });

  testWidgets('a short list sits just above the bottom bar', (tester) async {
    final router = _router();
    await tester.pumpWidget(_wrap(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final screenHeight = tester.getSize(find.byType(TasksScreen)).height;
    // The rows end near the bar, not at the top of the screen.
    expect(
      tester.getTopLeft(find.text('standalone')).dy,
      greaterThan(screenHeight / 2),
    );
  });

  testWidgets('a long list opens at its top, overdue tasks first', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final router = _router();
    await tester.pumpWidget(
      _wrap(
        router,
        standaloneItems: [
          TaskListItem.task(_task('atrasada', dueDate: yesterday)),
          for (var i = 0; i < 30; i++) TaskListItem.task(_task('tarefa $i')),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('atrasada'), findsOneWidget);
    final top = tester.getTopLeft(find.text('atrasada')).dy;
    expect(top, lessThan(200));
    // The end of the list is below the fold.
    final screenHeight = tester.getSize(find.byType(TasksScreen)).height;
    expect(
      tester.getTopLeft(find.text('Concluídas')).dy,
      greaterThan(screenHeight),
    );
  });
}
