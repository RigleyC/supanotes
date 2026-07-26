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

    await tester.pumpWidget(_buildSheetForTask(task));
    await tester.pumpAndSettle();

    expect(find.text('Editar horário e frequência'), findsOneWidget);
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

  testWidgets('cancel does not persist metadata changes', (tester) async {
    final task = _task(id: 'task-cancel');
    var saveCalls = 0;

    await tester.pumpWidget(
      _buildSheetForTask(
        task,
        onSave: ({dueDate, hasTime = false, recurrence, reminder}) async {
          saveCalls++;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(saveCalls, 0);
  });

  testWidgets('save persists once and closes after success', (tester) async {
    final task = _task(id: 'task-save');
    var saveCalls = 0;

    await tester.pumpWidget(
      _buildSheetForTask(
        task,
        onSave: ({dueDate, hasTime = false, recurrence, reminder}) async {
          saveCalls++;
          expect(dueDate, task.dueDate);
          expect(recurrence, task.recurrence);
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saveCalls, 1);
    expect(find.byType(TaskMetadataSheetBody), findsNothing);
  });

  testWidgets('save failure keeps modal open and retry can succeed', (
    tester,
  ) async {
    final task = _task(id: 'task-retry');
    var saveCalls = 0;
    var shouldFail = true;

    await tester.pumpWidget(
      _buildSheetForTask(
        task,
        onSave: ({dueDate, hasTime = false, recurrence, reminder}) async {
          saveCalls++;
          if (shouldFail) throw StateError('save failed');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saveCalls, 1);
    expect(find.byType(TaskMetadataSheetBody), findsOneWidget);
    expect(find.textContaining('save failed'), findsOneWidget);

    shouldFail = false;
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(saveCalls, 2);
    expect(find.byType(TaskMetadataSheetBody), findsNothing);
  });
}

Widget _buildSheetForTask(
  TaskModel task, {
  Future<void> Function({
    required DateTime? dueDate,
    required bool hasTime,
    required TaskRecurrence? recurrence,
    required String? reminder,
  })?
  onSave,
}) {
  return ProviderScope(
    child: _ProviderInitializer(
      task: task,
      child: MaterialApp(
        home: Scaffold(
          body: TaskMetadataSheetBody(
            noteId: task.noteId,
            taskId: task.id,
            onSave: onSave,
          ),
        ),
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
