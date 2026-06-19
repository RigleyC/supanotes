import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/presentation/widgets/custom_divider_component.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('renders with explicit divider index', (tester) async {
    await tester.pumpWidget(
      wrap(
        CustomDividerComponent(
          componentKey: GlobalKey(),
          dividerIndex: 7,
          caretColor: Colors.black,
        ),
      ),
    );

    expect(find.byType(CustomDividerComponent), findsOneWidget);
  });

  testWidgets('renders with default index when none provided', (tester) async {
    await tester.pumpWidget(
      wrap(
        CustomDividerComponent(
          componentKey: GlobalKey(),
          dividerIndex: null,
          caretColor: Colors.black,
        ),
      ),
    );

    expect(find.byType(CustomDividerComponent), findsOneWidget);
  });
}
