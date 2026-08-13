import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_controller.dart';
import 'package:supanotes/features/tasks/presentation/controllers/task_metadata_draft.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_sheet.dart';
import '../../../../helpers/haptic_test_helper.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  testWidgets('renders metadata pickers for existing task', (tester) async {
    final now = DateTime.utc(2026, 6, 11);
    final task = _SheetTask(
      id: 'task-1',
      draft: TaskMetadataDraft(
        scheduleAnchor: now,
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        reminder: null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _MetadataSheetLauncher(task: task, onSave: (_) async {}),
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
    final task = _SheetTask(
      id: 'task-1',
      draft: TaskMetadataDraft(
        scheduleAnchor: now,
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        reminder: null,
      ),
    );

    await tester.pumpWidget(_buildSheetForTask(task));

    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('does not show delete button', (tester) async {
    final now = DateTime.utc(2026, 6, 11);
    final task = _SheetTask(
      id: 'task-1',
      draft: TaskMetadataDraft(
        scheduleAnchor: now,
        recurrence: TaskRecurrence.daily,
        hasTime: false,
        reminder: null,
      ),
    );

    await tester.pumpWidget(_buildSheetForTask(task));

    expect(find.text('Excluir'), findsNothing);
  });

  testWidgets('shows dynamic weekly label with day of week', (tester) async {
    final thursday = DateTime.utc(2026, 6, 11);
    final t = _SheetTask(
      id: 'task-2',
      draft: TaskMetadataDraft(
        scheduleAnchor: thursday,
        recurrence: TaskRecurrence.weekly,
        hasTime: false,
        reminder: null,
      ),
    );

    await tester.pumpWidget(_buildSheetForTask(t));
    await tester.pumpAndSettle();

    expect(find.text('Semanalmente, às quinta-feira'), findsOneWidget);
  });

  testWidgets('shows dynamic monthly label with day of month', (tester) async {
    final fifteenth = DateTime.utc(2026, 7, 15);
    final t = _SheetTask(
      id: 'task-3',
      draft: TaskMetadataDraft(
        scheduleAnchor: fifteenth,
        recurrence: TaskRecurrence.monthly,
        hasTime: false,
        reminder: null,
      ),
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

  testWidgets('opening the date page emits one control haptic', (tester) async {
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);
    final task = _taskWithoutMetadata(id: 'task-date-open-haptic');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _MetadataSheetLauncher(task: task, onSave: (_) async {}),
        ),
      ),
    );

    await tester.tap(find.text('Abrir metadados'));
    await tester.pumpAndSettle();

    recorder.calls.clear();
    await tester.tap(find.text('Adicionar data'));
    await tester.pumpAndSettle();

    expect(find.text('Escolher data'), findsOneWidget);
    expect(
      recorder.calls.where(
        (call) => call.arguments == 'HapticFeedbackType.lightImpact',
      ),
      hasLength(1),
    );
  });

  testWidgets('modal selections persist date and recurrence', (tester) async {
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
            onSave: (draft) async {
              saveCalls++;
              savedDueDate = draft.scheduleAnchor;
              savedRecurrence = draft.recurrence;
              savedHasTime = draft.hasTime;
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
              onSave: (draft) async {
                saveCalls++;
                savedDueDate = draft.scheduleAnchor;
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

  testWidgets('clearing an existing date emits one control haptic', (
    tester,
  ) async {
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);
    final task = _task(id: 'task-date-clear-haptic');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: _MetadataSheetLauncher(task: task, onSave: (_) async {}),
        ),
      ),
    );

    await tester.tap(find.text('Abrir metadados'));
    await tester.pumpAndSettle();

    expect(find.text('Adicionar data'), findsNothing);

    recorder.calls.clear();
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    expect(find.text('Adicionar data'), findsOneWidget);
    expect(
      recorder.calls.where(
        (call) => call.arguments == 'HapticFeedbackType.lightImpact',
      ),
      hasLength(1),
    );
  });
}

Widget _buildSheetForTask(_SheetTask task) {
  return ProviderScope(
    child: _ProviderInitializer(
      task: task,
      child: MaterialApp(
        home: Scaffold(body: TaskMetadataSheetBody(taskId: task.id)),
      ),
    ),
  );
}

_SheetTask _task({String id = 'task-1'}) {
  final now = DateTime.utc(2026, 6, 11);
  return _SheetTask(
    id: id,
    draft: TaskMetadataDraft(
      scheduleAnchor: now,
      recurrence: TaskRecurrence.daily,
      hasTime: false,
      reminder: null,
    ),
  );
}

_SheetTask _taskWithoutMetadata({required String id}) {
  return _SheetTask(
    id: id,
    draft: const TaskMetadataDraft(
      scheduleAnchor: null,
      hasTime: false,
      recurrence: null,
      reminder: null,
    ),
  );
}

class _ProviderInitializer extends ConsumerWidget {
  const _ProviderInitializer({required this.task, required this.child});
  final _SheetTask task;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taskMetadataProvider(task.id).notifier).initialize(task.draft);
    });
    return child;
  }
}

class _MetadataSheetLauncher extends ConsumerWidget {
  const _MetadataSheetLauncher({required this.task, required this.onSave});

  final _SheetTask task;
  final Future<void> Function(TaskMetadataDraft draft) onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: TextButton(
        onPressed: () => showTaskMetadataSheet(
          context: context,
          ref: ref,
          taskId: task.id,
          draft: task.draft,
          onSave: onSave,
        ),
        child: const Text('Abrir metadados'),
      ),
    );
  }
}

class _SheetTask {
  const _SheetTask({required this.id, required this.draft});

  final String id;
  final TaskMetadataDraft draft;
}
