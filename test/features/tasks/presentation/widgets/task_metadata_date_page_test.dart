import 'package:family_bottom_sheet/family_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_date_page.dart';
import 'package:supanotes/shared/widgets/global_sheet.dart';

import '../../../../helpers/haptic_test_helper.dart';

void main() {
  testWidgets('uses the legacy Material calendar icon for quick dates', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskMetadataDatePage(selected: null, onSelected: (_) {}),
      ),
    );

    expect(find.byIcon(Icons.calendar_month_rounded), findsNWidgets(3));
  });

  testWidgets('shows the complete calendar without an inner scroll view', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskMetadataDatePage(selected: null, onSelected: (_) {}),
      ),
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('aligns task tiles with the sheet title', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskMetadataDatePage(selected: null, onSelected: (_) {}),
      ),
    );

    final titleLeft = tester.getTopLeft(find.text('Escolher data')).dx;
    final tileLeadingLeft = tester
        .getTopLeft(find.byIcon(Icons.calendar_month_rounded).first)
        .dx;

    expect(tileLeadingLeft, titleLeft);
  });

  testWidgets(
    'quick date selection emits one selection haptic and returns to the root page',
    (tester) async {
      final recorder = HapticTestRecorder()..install();
      addTearDown(recorder.dispose);
      DateTime? selectedDate;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showGlobalSheet<void>(
                  context: context,
                  builder: (sheetContext) => GlobalSheetPage(
                    title: 'Página principal',
                    child: Center(
                      child: TextButton(
                        onPressed: () =>
                            FamilyModalSheet.of(sheetContext).pushPage(
                              TaskMetadataDatePage(
                                selected: null,
                                onSelected: (date) {
                                  selectedDate = date;
                                },
                              ),
                            ),
                        child: const Text('Abrir página de data'),
                      ),
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir página de data'));
      await tester.pumpAndSettle();

      expect(find.text('Escolher data'), findsOneWidget);

      recorder.calls.clear();
      await tester.tap(find.text('Hoje'));
      await tester.pumpAndSettle();

      expect(DateUtils.isSameDay(selectedDate, DateTime.now()), isTrue);
      expect(find.text('Página principal'), findsOneWidget);
      expect(find.text('Escolher data'), findsNothing);
      expect(
        recorder.calls.where(
          (call) => call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('reselecting the active quick date emits no haptic', (
    tester,
  ) async {
    final recorder = HapticTestRecorder()..install();
    addTearDown(recorder.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showGlobalSheet<void>(
                context: context,
                builder: (_) => TaskMetadataDatePage(
                  selected: DateTime.now(),
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
    recorder.calls.clear();
    await tester.tap(find.text('Hoje'));

    expect(recorder.count('HapticFeedbackType.selectionClick'), 0);
  });
}
