import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/features/settings/presentation/widgets/new_context_sheet.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

class _MockSettingsRepository extends Mock implements ISettingsRepository {}

void main() {
  testWidgets('renders title, field and buttons', (tester) async {
    final repo = _MockSettingsRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: NewContextSheet()),
      ),
    ));
    expect(find.text('Novo contexto'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Criar'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('shows validation error on empty submit', (tester) async {
    final repo = _MockSettingsRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: NewContextSheet()),
      ),
    ));
    await tester.tap(find.text('Criar'));
    await tester.pump();
    expect(find.text('Digite um nome.'), findsOneWidget);
  });

  testWidgets('shows error from ApiException', (tester) async {
    final repo = _MockSettingsRepository();
    when(() => repo.createContext(any())).thenThrow(
      const ConflictException(message: 'slug already exists'),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: NewContextSheet()),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Work');
    await tester.tap(find.text('Criar'));
    await tester.pump();
    expect(find.text('slug already exists'), findsOneWidget);
  });
}
