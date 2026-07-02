import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/tasks/presentation/widgets/recurrence_picker.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

void main() {
  testWidgets('renders recurrence options', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecurrencePicker(
            initialRecurrence: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Nenhuma'), findsOneWidget);
    expect(find.text('Diariamente'), findsOneWidget);
    expect(find.text('Dias úteis'), findsOneWidget);
    expect(find.text('Semanalmente'), findsOneWidget);
    expect(find.text('Mensalmente'), findsOneWidget);
    expect(find.byType(AppSelectionTile), findsNWidgets(5));
  });
}
