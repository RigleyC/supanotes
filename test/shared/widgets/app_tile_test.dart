import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';

void main() {
  testWidgets('renders a one-line tile with leading and trailing widgets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTile(
            title: 'Data',
            leading: const Icon(Icons.calendar_today),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Data'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(GestureDetector), findsOneWidget);
  });

  testWidgets('renders subtitle and calls onTap when enabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTile(
            title: 'Conta',
            subtitle: 'user@example.com',
            onTap: () => taps++,
          ),
        ),
      ),
    );

    expect(find.text('user@example.com'), findsOneWidget);
    await tester.tap(find.text('Conta'));
    expect(taps, 1);
  });

  testWidgets('does not call onTap when disabled', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTile(title: 'Conta', enabled: false, onTap: () => taps++),
        ),
      ),
    );

    await tester.tap(find.text('Conta'));
    expect(taps, 0);
  });

  testWidgets('marks the tile selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppTile(title: 'Hoje', selected: true)),
      ),
    );

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('does not trigger the tile when trailing action is pressed', (
    tester,
  ) async {
    var tileTaps = 0;
    var trailingTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTile(
            title: 'Data',
            onTap: () => tileTaps++,
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => trailingTaps++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close_rounded));

    expect(trailingTaps, 1);
    expect(tileTaps, 0);
  });

  testWidgets('exposes a tappable button semantic', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTile(title: 'Data', onTap: () {}),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(AppTile));
    expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('animates to the pressed scale without owning the callback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTile(title: 'Data', onTap: () {}),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Data')),
    );
    await tester.pump(const Duration(seconds: 1));

    final pressedMotion = tester.widget<SingleMotionBuilder>(
      find.byType(SingleMotionBuilder),
    );
    expect(pressedMotion.value, lessThan(1));

    await gesture.up();
    await tester.pump(const Duration(seconds: 1));

    final releasedMotion = tester.widget<SingleMotionBuilder>(
      find.byType(SingleMotionBuilder),
    );
    expect(releasedMotion.value, 1);
  });
}
