import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/features/tasks/application/task_controller.dart';
import 'package:supanotes/features/tasks/domain/task.dart';
import 'package:supanotes/features/tasks/presentation/task_editor_screen.dart';

class _MockTaskController extends Mock implements TaskController {}

void main() {
  setUpAll(() => registerFallbackValue(_task()));

  testWidgets('creates an independent task from the editor form', (
    tester,
  ) async {
    final controller = _MockTaskController();
    when(() => controller.create(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          taskControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const TaskEditorScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Comprar café');
    await tester.tap(find.byTooltip('Salvar'));
    await tester.pumpAndSettle();

    final created = verify(
      () => controller.create(captureAny()),
    ).captured.single;
    expect((created as Task).title, 'Comprar café');
    expect(created.ownerUserId, 'user-1');
  });

  testWidgets('updates an existing independent task with the edited data', (
    tester,
  ) async {
    final controller = _MockTaskController();
    when(() => controller.update(any())).thenAnswer((_) async {});
    final task = _task();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => TaskEditorScreen(task: task),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Título atualizado');
    await tester.tap(find.byTooltip('Salvar'));
    await tester.pumpAndSettle();

    final updated =
        verify(
              () => controller.update(captureAny()),
            ).captured.single
            as Task;
    expect(updated.id, task.id);
    expect(updated.ownerUserId, task.ownerUserId);
    expect(updated.title, 'Título atualizado');
  });

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

    expect(attempts, 2);
  });

  testWidgets('deletes an existing task through the dismiss gesture', (
    tester,
  ) async {
    final controller = _MockTaskController();
    when(() => controller.delete(any())).thenAnswer((_) async {});
    final task = _task();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [taskControllerProvider.overrideWithValue(controller)],
        child: MaterialApp(home: TaskEditorScreen(task: task)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byKey(const ValueKey('task-editor-dismissible')),
      const Offset(-500, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Excluir task?'), findsOneWidget);
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();

    verify(() => controller.delete(task.id)).called(1);
  });

  testWidgets('focuses the title field when the editor opens', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserIdProvider.overrideWithValue('user-1')],
        child: const MaterialApp(home: TaskEditorScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
  });
}

Task _task() {
  final now = DateTime.utc(2026, 9, 16);
  return Task(
    id: 'task-fallback',
    ownerUserId: 'user-1',
    title: 'Fallback',
    createdAt: now,
    updatedAt: now,
  );
}
