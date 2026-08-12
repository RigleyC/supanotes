import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/tasks/domain/task_model.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_controller.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  testWidgets('renders metadata pickers for existing task', (tester) async {
    final now = DateTime.utc(2026, 6, 11);
    final task = TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Comprar cafe',
      status: 'open',
      position: '0',
      dueDate: now,
      completedAt: null,
      recurrence: TaskRecurrence.daily,
      hasTime: false,
      reminder: null,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _MetadataSheetLauncher(
            task: task,
            onSave: ({dueDate, hasTime = false, recurrence, reminder}) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir metadados'));
    await tester.pumpAndSettle();

    expect(find.text('Editar horário e frequência'), findsOneWidget);
    expect(find.byTooltip('Fechar'), findsOneWidget);
    expect(find.text('Diariamente'), findsOneWidget);
  });

  testWidgets('does not show title input', (tester) async {
    final now = DateTime.utc(2026, 6, 11);
    final task = TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Comprar cafe',
      status: 'open',
      position: '0',
      dueDate: now,
      completedAt: null,
      recurrence: TaskRecurrence.daily,
      hasTime: false,
      reminder: null,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(_buildSheetForTask(task));

    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('does not show delete button', (tester) async {
    final now = DateTime.utc(2026, 6, 11);
    final task = TaskModel(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Comprar cafe',
      status: 'open',
      position: '0',
      dueDate: now,
      completedAt: null,
      recurrence: TaskRecurrence.daily,
      hasTime: false,
      reminder: null,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(_buildSheetForTask(task));

    expect(find.text('Excluir'), findsNothing);
  });

  testWidgets('shows dynamic weekly label with day of week', (tester) async {
    final thursday = DateTime.utc(2026, 6, 11);
    final t = TaskModel(
      id: 'task-2',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Tarefa semanal',
      status: 'open',
      position: '0',
      dueDate: thursday,
      completedAt: null,
      recurrence: TaskRecurrence.weekly,
      hasTime: false,
      reminder: null,
      createdAt: thursday,
      updatedAt: thursday,
    );

    await tester.pumpWidget(_buildSheetForTask(t));
    await tester.pumpAndSettle();

    expect(find.text('Semanalmente, às quinta-feira'), findsOneWidget);
  });

  testWidgets('shows dynamic monthly label with day of month', (tester) async {
    final fifteenth = DateTime.utc(2026, 7, 15);
    final t = TaskModel(
      id: 'task-3',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Tarefa mensal',
      status: 'open',
      position: '0',
      dueDate: fifteenth,
      completedAt: null,
      recurrence: TaskRecurrence.monthly,
      hasTime: false,
      reminder: null,
      createdAt: fifteenth,
      updatedAt: fifteenth,
    );

    await tester.pumpWidget(_buildSheetForTask(t));
    await tester.pumpAndSettle();

    expect(find.text('Mensalmente, em 15'), findsOneWidget);
  });

  testWidgets('does not render explicit save or cancel buttons', (
    tester,
  ) async {
    await tester.pumpWidget(_buildSheetForTask(_task()));

    expect(find.text('Salvar'), findsNothing);
    expect(find.text('Cancelar'), findsNothing);
  });

  testWidgets('modal selections persist date and recurrence', (
    tester,
  ) async {
    final task = _taskWithoutMetadata(id: 'task-modal-selection');
    DateTime? savedDueDate;
    TaskRecurrence? savedRecurrence;
    var savedHasTime = false;
    var saveCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _MetadataSheetLauncher(
            task: task,
            onSave: ({dueDate, hasTime = false, recurrence, reminder}) async {
              saveCalls++;
              savedDueDate = dueDate;
              savedRecurrence = recurrence;
              savedHasTime = hasTime;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir metadados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoje'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar horário'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirmar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar recorrência'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diariamente'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(savedDueDate, isNotNull);
    expect(savedHasTime, isTrue);
    expect(savedRecurrence, TaskRecurrence.daily);
    expect(saveCalls, 1);
  });

  testWidgets(
    'internal page close returns to root and resolves save only on root dismissal',
    (tester) async {
      final task = _taskWithoutMetadata(id: 'task-internal-close');
      DateTime? savedDueDate;
      var saveCalls = 0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: _MetadataSheetLauncher(
              task: task,
              onSave: ({dueDate, hasTime = false, recurrence, reminder}) async {
                saveCalls++;
                savedDueDate = dueDate;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir metadados'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Adicionar data'));
      await tester.pumpAndSettle();

      expect(find.text('Escolher data'), findsOneWidget);
      expect(find.text('Editar horário e frequência'), findsNothing);

      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Editar horário e frequência'), findsOneWidget);
      expect(find.text('Escolher data'), findsNothing);
      expect(saveCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(saveCalls, 1);
      expect(savedDueDate, isNull);
    },
  );
}

Widget _buildSheetForTask(TaskModel task) {
  return ProviderScope(
    child: _ProviderInitializer(
      task: task,
      child: MaterialApp(
        home: Scaffold(body: TaskMetadataSheetBody(taskId: task.id)),
      ),
    ),
  );
}

TaskModel _task({String id = 'task-1'}) {
  final now = DateTime.utc(2026, 6, 11);
  return TaskModel(
    id: id,
    userId: 'user-1',
    noteId: 'note-1',
    title: 'Comprar cafe',
    status: 'open',
    position: '0',
    dueDate: now,
    completedAt: null,
    recurrence: TaskRecurrence.daily,
    hasTime: false,
    reminder: null,
    createdAt: now,
    updatedAt: now,
  );
}

TaskModel _taskWithoutMetadata({required String id}) {
  final now = DateTime.utc(2026, 6, 11);
  return TaskModel(
    id: id,
    userId: 'user-1',
    noteId: 'note-1',
    title: 'Comprar cafe',
    status: 'open',
    position: '0',
    dueDate: null,
    completedAt: null,
    recurrence: null,
    hasTime: false,
    reminder: null,
    createdAt: now,
    updatedAt: now,
  );
}

class _ProviderInitializer extends ConsumerWidget {
  const _ProviderInitializer({required this.task, required this.child});
  final TaskModel task;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taskMetadataProvider(task.id).notifier).initialize(task);
    });
    return child;
  }
}

class _MetadataSheetLauncher extends ConsumerWidget {
  const _MetadataSheetLauncher({required this.task, required this.onSave});

  final TaskModel task;
  final Future<void> Function({
    required DateTime? dueDate,
    required bool hasTime,
    required TaskRecurrence? recurrence,
    required String? reminder,
  })
  onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: TextButton(
        onPressed: () => showTaskMetadataSheet(
          context: context,
          ref: ref,
          task: task,
          onSave: onSave,
        ),
        child: const Text('Abrir metadados'),
      ),
    );
  }
}
