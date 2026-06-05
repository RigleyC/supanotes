import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/features/auth/data/auth_local_storage.dart';
import 'package:supanotes/features/auth/data/auth_repository.dart';
import 'package:supanotes/features/auth/domain/auth_state.dart';
import 'package:supanotes/main.dart';
import 'package:supanotes/shared/widgets/splash_screen.dart';

class _MockAuthLocalStorage extends Mock implements AuthLocalStorage {}

class _MockAuthRepository extends Mock implements AuthRepository {}

/// Stub [AuthController] whose [build] resolves immediately to
/// [AuthUnauthenticated].
///
/// In widget tests we never need the real controller (which would
/// touch the secure-storage platform channel and fail without a
/// binding), so we override the provider with this stub. The router's
/// redirect treats AuthUnauthenticated at `/` as "stay on the splash",
/// which is exactly what the assertions below expect.
class _StubAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

Widget _wrapApp() {
  final storage = _MockAuthLocalStorage();
  final repository = _MockAuthRepository();
  when(() => storage.getAccessToken()).thenAnswer((_) async => null);
  when(() => storage.getRefreshToken()).thenAnswer((_) async => null);
  when(() => storage.getUserId()).thenAnswer((_) async => null);
  when(() => storage.getUserEmail()).thenAnswer((_) async => null);
  when(() => storage.getUserName()).thenAnswer((_) async => null);
  when(() => storage.clear()).thenAnswer((_) async {});

  return UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        authLocalStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith(_StubAuthController.new),
      ],
    ),
    child: const SupaNotesApp(),
  );
}

void main() {
  testWidgets('SplashScreen renders the app name', (tester) async {
    await tester.pumpWidget(_wrapApp());
    await tester.pump();

    expect(find.text(AppConstants.appName), findsOneWidget);
  });

  testWidgets('SplashScreen uses the dark theme by default',
      (tester) async {
    await tester.pumpWidget(_wrapApp());
    await tester.pump();

    final BuildContext context = tester.element(find.byType(SplashScreen));
    final ThemeData theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.brightness, Brightness.dark);
  });

  testWidgets('SupaNotesApp is const-constructible', (tester) async {
    // Smoke test: SupaNotesApp must be a const widget so it can be embedded
    // inside `const ProviderScope` and rebuilt cheaply on every hot reload.
    expect(const SupaNotesApp(), isA<SupaNotesApp>());
  });
}
