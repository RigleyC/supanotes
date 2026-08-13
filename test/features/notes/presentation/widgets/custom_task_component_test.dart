import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:super_editor/super_editor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/custom_task_component.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/domain/task_reminder_option.dart';
import 'package:flutter/material.dart';

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
}
