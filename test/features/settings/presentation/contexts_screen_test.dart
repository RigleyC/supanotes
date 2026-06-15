import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/features/settings/presentation/contexts_screen.dart';
import 'package:supanotes/features/settings/presentation/controllers/contexts_controller.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _MockSettingsRepo extends Mock implements ISettingsRepository {}

Widget buildApp({required ProviderContainer container}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const ContextsScreen(),
    ),
  );
}

void main() {
  group('ContextsScreen', () {
    testWidgets('shows empty state when no contexts', (tester) async {
      final container = ProviderContainer(
        overrides: [
          contextsProvider.overrideWithValue(
            const AsyncValue<List<UserContext>>.data([]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      expect(find.text('Nenhum contexto ainda'), findsOneWidget);
    });

    testWidgets('renders list of contexts', (tester) async {
      final container = ProviderContainer(
        overrides: [
          contextsProvider.overrideWithValue(
            AsyncValue<List<UserContext>>.data([
              UserContext(
                id: 'c-1',
                slug: 'work',
                name: 'Trabalho',
                createdAt: DateTime(2025, 1, 1),
                updatedAt: DateTime(2025, 6, 1),
              ),
              UserContext(
                id: 'c-2',
                slug: 'personal',
                name: 'Pessoal',
                createdAt: DateTime(2025, 2, 1),
                updatedAt: DateTime(2025, 6, 1),
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      expect(find.text('Trabalho'), findsOneWidget);
      expect(find.text('Pessoal'), findsOneWidget);
      expect(find.text('work'), findsOneWidget);
      expect(find.text('personal'), findsOneWidget);
    });

    testWidgets('shows error state', (tester) async {
      final container = ProviderContainer(
        overrides: [
          contextsProvider.overrideWithValue(
            AsyncValue<List<UserContext>>.error(
              Exception('Failed to load'),
              StackTrace.current,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      expect(find.text('Exception: Failed to load'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('delete button shows confirmation dialog', (tester) async {
      final repo = _MockSettingsRepo();
      when(() => repo.deleteContext(any())).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [
          contextsProvider.overrideWithValue(
            AsyncValue<List<UserContext>>.data(<UserContext>[
              UserContext(
                id: 'c-1',
                slug: 'work',
                name: 'Trabalho',
                createdAt: DateTime(2025, 1, 1),
                updatedAt: DateTime(2025, 6, 1),
              ),
            ]),
          ),
          settingsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildApp(container: container));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(find.text('Apagar contexto?'), findsOneWidget);
    });
  });
}
