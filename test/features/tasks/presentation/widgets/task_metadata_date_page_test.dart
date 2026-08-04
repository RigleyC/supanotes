import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/presentation/widgets/task_metadata_date_page.dart';

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
}
