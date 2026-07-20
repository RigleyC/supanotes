import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('pt_BR', null);
  });

  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('shows no badges when due date and recurrence are absent', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TaskMetadataBadges()));

    expect(find.byIcon(Icons.event_outlined), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
  });

  testWidgets('shows Hoje for today due date', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await tester.pumpWidget(wrap(TaskMetadataBadges(dueDate: today)));

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.text('Hoje'), findsOneWidget);
  });

  testWidgets('shows recurrence label', (tester) async {
    await tester.pumpWidget(
      wrap(const TaskMetadataBadges(recurrence: TaskRecurrence.weekly)),
    );

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });

  testWidgets('does not show Atrasada for past due dates when completed', (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));

    await tester.pumpWidget(
      wrap(TaskMetadataBadges(dueDate: yesterday, isCompleted: true)),
    );

    expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    expect(find.textContaining('Atrasada'), findsNothing);
  });

  testWidgets('shows short recurrence label when dueDate is set', (tester) async {
    final thursday = DateTime.utc(2026, 6, 11);

    await tester.pumpWidget(
      wrap(TaskMetadataBadges(
        dueDate: thursday,
        recurrence: TaskRecurrence.weekly,
      )),
    );

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
  });

  testWidgets('shows short monthly label when dueDate is set', (tester) async {
    final fifteenth = DateTime.utc(2026, 7, 15);

    await tester.pumpWidget(
      wrap(TaskMetadataBadges(
        dueDate: fifteenth,
        recurrence: TaskRecurrence.monthly,
      )),
    );

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Mensalmente'), findsOneWidget);
  });
}
