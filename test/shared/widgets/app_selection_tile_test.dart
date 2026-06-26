import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/shared/widgets/app_selection_tile.dart';

void main() {
  testWidgets('renders label and icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelectionTile(
            label: 'Test Label',
            icon: Icons.ac_unit,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Test Label'), findsOneWidget);
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
  });

  testWidgets('calls onTap when pressed', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelectionTile(
            label: 'Tap Me',
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tap Me'));
    expect(tapped, isTrue);
  });
}
