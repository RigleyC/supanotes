import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/main.dart';

void main() {
  testWidgets('SplashScreen renders the app name', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: SupaNotesApp()),
    );

    // Pump once more so the async font load has a chance to settle. We do
    // not call pumpAndSettle because the (intentional) splash has no
    // animations and pumpAndSettle would hang on a never-completing
    // google_fonts fetch in the test environment.
    await tester.pump();

    expect(find.text(AppConstants.appName), findsOneWidget);
  });

  testWidgets('SplashScreen uses the dark theme by default', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: SupaNotesApp()),
    );
    await tester.pump();

    final BuildContext context = tester.element(find.byType(SplashScreen));
    final ThemeData theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
  });

  testWidgets('SupaNotesApp is const-constructible', (WidgetTester tester) async {
    // Smoke test: SupaNotesApp must be a const widget so it can be embedded
    // inside `const ProviderScope` and rebuilt cheaply on every hot reload.
    expect(const SupaNotesApp(), isA<SupaNotesApp>());
  });
}
