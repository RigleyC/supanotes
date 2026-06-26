import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/presentation/controllers/soul_editor_controller.dart';
import 'package:supanotes/features/settings/presentation/soul_editor_screen.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _DataSoulNotifier extends SoulNotifier {
  _DataSoulNotifier(this._soul);
  final Soul _soul;
  @override
  Future<SoulState> build() async => SoulState(soul: _soul);
}

class _LoadingSoulNotifier extends SoulNotifier {
  @override
  Future<SoulState> build() async => Completer<SoulState>().future;
}

class _ErrorSoulNotifier extends SoulNotifier {
  @override
  Future<SoulState> build() async => throw Exception('server error');
}

Widget buildApp({required ProviderContainer container}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const SoulEditorScreen(),
    ),
  );
}

void main() {
  group('SoulEditorScreen', () {
    testWidgets('shows loading indicator', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWith(() => _LoadingSoulNotifier()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders editor with loaded soul text', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWith(
            () => _DataSoulNotifier(
              const Soul(personality: 'Seja útil e direto.'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);
      expect(find.text('Restaurar padrão'), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWith(() => _ErrorSoulNotifier()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      // Allow the async build to complete with an error
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.text('Exception: server error'), findsOneWidget);
    });

    testWidgets('restore default opens confirmation dialog', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWith(
            () => _DataSoulNotifier(
              const Soul(personality: 'Seja útil e direto.'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      await tester.tap(find.text('Restaurar padrão'));
      await tester.pump();
      expect(
        find.text('Restaurar personalidade padrão?'),
        findsOneWidget,
      );
    });
  });
}
