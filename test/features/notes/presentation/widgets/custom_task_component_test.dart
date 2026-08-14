import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:flutter/material.dart';

import '../../../../helpers/haptic_test_helper.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  test('keeps task metadata when the component view model is copied', () {
    final node = TaskNode(
      id: 'task-1',
      text: AttributedText('Review task'),
      isComplete: false,
      metadata: const {
        'dueDate': '2099-01-02T10:00:00.000Z',
        'hasTime': true,
        'recurrenceRule': 'weekly',
        'reminder': 'at_time',
      },
    );
    final document = MutableDocument(nodes: [node]);
    final viewModel = CustomTaskComponentBuilder().createViewModel(
      document,
      node,
    );

    expect(viewModel, isA<CustomTaskComponentViewModel>());

    final copied = viewModel!.copy();

    expect(copied, isA<CustomTaskComponentViewModel>());
    final customCopy = copied as CustomTaskComponentViewModel;
    expect(
      customCopy.taskMetadata.scheduleAnchor,
      DateTime.utc(2099, 1, 2, 10),
    );
    expect(customCopy.taskMetadata.hasTime, isTrue);
    expect(customCopy.taskMetadata.recurrence, TaskRecurrence.weekly);
    expect(customCopy.taskMetadata.reminder, TaskReminderOption.atTime);
  });

  testWidgets('renders task metadata inside SuperEditor', (tester) async {
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Review task'),
          isComplete: false,
          metadata: const {
            'dueDate': '2099-01-02T10:00:00.000Z',
            'hasTime': true,
            'recurrenceRule': 'weekly',
            'reminder': 'at_time',
          },
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperEditor(
            editor: editor,
            componentBuilders: [CustomTaskComponentBuilder()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
  });

  testWidgets('task completion emits one medium impact haptic', (tester) async {
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);
    var completionCalls = 0;
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Review task'),
          isComplete: false,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperEditor(
            editor: editor,
            componentBuilders: [
              CustomTaskComponentBuilder(
                onTaskComplete: (_) async {
                  completionCalls++;
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    recorder.calls.clear();
    await tester.tap(find.bySemanticsLabel('Concluir tarefa'));
    await tester.pumpAndSettle();

    expect(completionCalls, 1);
    expect(
      recorder.calls.where(
        (call) => call.arguments == 'HapticFeedbackType.mediumImpact',
      ),
      hasLength(1),
    );
  });

  testWidgets('task long press calls the callback when configured', (
    tester,
  ) async {
    var longPressCalls = 0;
    final document = MutableDocument(
      nodes: [
        TaskNode(
          id: 'task-1',
          text: AttributedText('Review task'),
          isComplete: false,
        ),
      ],
    );
    final editor = createDefaultDocumentEditor(
      document: document,
      composer: MutableDocumentComposer(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SuperEditor(
            editor: editor,
            componentBuilders: [
              CustomTaskComponentBuilder(
                onTaskLongPress: (_) => longPressCalls++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final taskTopLeft = tester.getTopLeft(find.byType(CustomTaskComponent));
    await tester.longPressAt(taskTopLeft + const Offset(16, 20));
    await tester.pumpAndSettle();

    expect(longPressCalls, 1);
  });
}
