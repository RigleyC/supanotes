import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/settings/presentation/widgets/settings_tile.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

Widget buildApp(Widget child) {
  return MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));
}

void main() {
  group('SettingsTile.navigation', () {
    testWidgets('renders title and icon', (tester) async {
      await tester.pumpWidget(buildApp(
        const SettingsTile.navigation(
          icon: Icons.folder_outlined,
          title: 'Contextos',
        ),
      ));
      expect(find.text('Contextos'), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('fires onTap when enabled', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildApp(
        SettingsTile.navigation(
          icon: Icons.folder_outlined,
          title: 'Contextos',
          onTap: () => tapped = true,
        ),
      ));
      await tester.tap(find.text('Contextos'));
      expect(tapped, isTrue);
    });

    testWidgets('does not fire onTap when disabled', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildApp(
        SettingsTile.navigation(
          icon: Icons.folder_outlined,
          title: 'Contextos',
          onTap: () => tapped = true,
          enabled: false,
        ),
      ));
      await tester.tap(find.text('Contextos'));
      expect(tapped, isFalse);
    });

    testWidgets('renders subtitle', (tester) async {
      await tester.pumpWidget(buildApp(
        const SettingsTile.navigation(
          icon: Icons.folder_outlined,
          title: 'Contextos',
          subtitle: 'Pastas que agrupam suas notas.',
        ),
      ));
      expect(find.text('Pastas que agrupam suas notas.'), findsOneWidget);
    });
  });

  group('SettingsTile.toggle', () {
    testWidgets('renders switch with given value', (tester) async {
      await tester.pumpWidget(buildApp(
        SettingsTile.toggle(
          icon: Icons.notifications_outlined,
          title: 'Receber push',
          value: true,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('Receber push'), findsOneWidget);
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('fires onChanged when tapped', (tester) async {
      bool? newValue;
      await tester.pumpWidget(buildApp(
        SettingsTile.toggle(
          icon: Icons.notifications_outlined,
          title: 'Receber push',
          value: false,
          onChanged: (v) => newValue = v,
        ),
      ));
      await tester.tap(find.text('Receber push'));
      expect(newValue, isTrue);
    });
  });

  group('SettingsTile.action', () {
    testWidgets('renders title and fires onTap', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildApp(
        SettingsTile.action(
          icon: Icons.logout,
          title: 'Sair da conta',
          onTap: () => tapped = true,
        ),
      ));
      expect(find.text('Sair da conta'), findsOneWidget);
      await tester.tap(find.text('Sair da conta'));
      expect(tapped, isTrue);
    });
  });

  group('SettingsSectionHeader', () {
    testWidgets('renders uppercase title', (tester) async {
      await tester.pumpWidget(buildApp(
        const SettingsSectionHeader(title: 'Conta'),
      ));
      expect(find.text('CONTA'), findsOneWidget);
    });
  });
}
