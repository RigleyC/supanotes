import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_selection_page.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

import '../../../../helpers/haptic_test_helper.dart';

void main() {
  testWidgets('renders the selected option title in the primary color', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskMetadataSelectionPage<String>(
            title: 'Opção',
            selected: 'A',
            options: const ['A', 'B'],
            noneLabel: 'Nenhuma',
            optionLabel: (option) => option,
            optionIcon: (_) => Icons.circle,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final context = tester.element(find.text('A'));
    final primary = Theme.of(context).colorScheme.primary;
    final title = tester.widget<Text>(find.text('A'));

    expect(title.style?.color, primary);
  });

  testWidgets('reselecting none emits no selection haptic', (tester) async {
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showGlobalSheet<void>(
                context: context,
                builder: (_) => TaskMetadataSelectionPage<String>(
                  title: 'Opção',
                  selected: null,
                  options: const ['A'],
                  noneLabel: 'Nenhuma',
                  optionLabel: (option) => option,
                  optionIcon: (_) => Icons.circle,
                  onSelected: (_) {},
                ),
              ),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nenhuma'));

    expect(recorder.count('HapticFeedbackType.selectionClick'), 0);
  });
}
