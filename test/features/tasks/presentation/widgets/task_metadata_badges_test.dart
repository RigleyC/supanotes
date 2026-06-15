import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/domain/task_recurrence.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_badges.dart';

void main() {
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
}
