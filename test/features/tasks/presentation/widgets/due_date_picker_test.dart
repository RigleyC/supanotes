import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/utils/date_time_extensions.dart';
import 'package:supanotes/features/tasks/presentation/widgets/due_date_picker.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

void main() {
  group('DueDatePicker', () {
    Widget buildWidget({DateTime? initialDate, required ValueChanged<DateTime?> onChanged}) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DueDatePicker(
              initialDate: initialDate,
              onChanged: onChanged,
            ),
          ),
        ),
      );
    }

    testWidgets('renders all 5 quick-pick tiles', (tester) async {
      await tester.pumpWidget(buildWidget(initialDate: null, onChanged: (_) {}));

      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Amanhã'), findsOneWidget);
      expect(find.text('Próx. segunda'), findsOneWidget);
      expect(find.text('Escolher data'), findsOneWidget);
      expect(find.text('Sem data'), findsOneWidget);
      expect(find.byType(AppSelectionTile), findsNWidgets(5));
    });

    testWidgets('tapping Hoje emits today startOfDay', (tester) async {
      DateTime? result;
      await tester.pumpWidget(buildWidget(initialDate: null, onChanged: (d) => result = d));

      await tester.tap(find.text('Hoje'));
      await tester.pump();

      final today = DateTime.now().startOfDay;
      expect(result, isNotNull);
      expect(result!.year, today.year);
      expect(result!.month, today.month);
      expect(result!.day, today.day);
    });

    testWidgets('tapping Amanhã emits tomorrow', (tester) async {
      DateTime? result;
      await tester.pumpWidget(buildWidget(initialDate: null, onChanged: (d) => result = d));

      await tester.tap(find.text('Amanhã'));
      await tester.pump();

      final tomorrow = DateTime.now().startOfDay.add(const Duration(days: 1));
      expect(result, isNotNull);
      expect(result!.day, tomorrow.day);
    });

    testWidgets('tapping Escolher data expands the calendar', (tester) async {
      await tester.pumpWidget(buildWidget(initialDate: null, onChanged: (_) {}));

      expect(find.byType(CalendarDatePicker), findsNothing);

      await tester.tap(find.text('Escolher data'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarDatePicker), findsOneWidget);
    });

    testWidgets('tapping Sem data emits null', (tester) async {
      DateTime? result = DateTime.now();
      await tester.pumpWidget(buildWidget(initialDate: DateTime.now(), onChanged: (d) => result = d));

      await tester.tap(find.text('Sem data'));
      await tester.pump();

      expect(result, isNull);
    });

    testWidgets('calendar collapses after picking a date', (tester) async {
      DateTime? result;
      await tester.pumpWidget(buildWidget(initialDate: null, onChanged: (d) => result = d));

      // Open calendar
      await tester.tap(find.text('Escolher data'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);

      // Tap next month's 15th — find the first visible "15" day cell
      final dayFinder = find.text('15');
      await tester.tap(dayFinder.first);
      await tester.pumpAndSettle();

      // Calendar should collapse
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(result, isNotNull);
    });

    testWidgets('custom date tile shows formatted date label', (tester) async {
      // A date guaranteed not to be today/tomorrow/next-monday
      final customDate = DateTime(2030, 3, 15);
      await tester.pumpWidget(buildWidget(initialDate: customDate, onChanged: (_) {}));
      await tester.pump();

      expect(find.text('15 Mar'), findsOneWidget);
    });

    testWidgets('tile matching initialDate is selected', (tester) async {
      final today = DateTime.now().startOfDay;
      await tester.pumpWidget(buildWidget(initialDate: today, onChanged: (_) {}));

      final tiles = tester.widgetList<AppSelectionTile>(find.byType(AppSelectionTile)).toList();
      final todayTile = tiles.firstWhere((t) => t.label == 'Hoje');
      expect(todayTile.isSelected, isTrue);

      final nenhuma = tiles.firstWhere((t) => t.label == 'Sem data');
      expect(nenhuma.isSelected, isFalse);
    });
  });
}
