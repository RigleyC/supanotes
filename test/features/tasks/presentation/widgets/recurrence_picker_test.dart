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
    expect(find.text('Diária'), findsOneWidget);
    expect(find.text('Dias úteis'), findsOneWidget);
    expect(find.text('Semanal'), findsOneWidget);
    expect(find.text('Mensal'), findsOneWidget);
    expect(find.byType(AppSelectionTile), findsNWidgets(5));
  });
}
