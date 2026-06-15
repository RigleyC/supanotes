import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/presentation/controllers/soul_editor_controller.dart';
import 'package:supanotes/features/settings/presentation/soul_editor_screen.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

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
          soulProvider.overrideWithValue(
            const AsyncValue<Soul>.loading(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders editor with loaded soul text', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWithValue(
            const AsyncValue<Soul>.data(
              Soul(personality: 'Seja útil e direto.'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);
      expect(find.text('Restaurar padrão'), findsOneWidget);
    });

    testWidgets('toggle preview mode', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWithValue(
            const AsyncValue<Soul>.data(
              Soul(personality: 'Seja útil e direto.'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      expect(find.text('Visualizar'), findsOneWidget);
      expect(find.text('Seja útil e direto.'), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWithValue(
            AsyncValue<Soul>.error(
              Exception('server error'),
              StackTrace.current,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      expect(find.text('Exception: server error'), findsOneWidget);
    });

    testWidgets('restore default opens confirmation dialog', (tester) async {
      final container = ProviderContainer(
        overrides: [
          soulProvider.overrideWithValue(
            const AsyncValue<Soul>.data(
              Soul(personality: 'Seja útil e direto.'),
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
