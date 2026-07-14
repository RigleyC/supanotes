import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/settings/presentation/settings_screen.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/core/notifications/push_service.dart';

class _TestAuthController extends AuthController {
  _TestAuthController(this._user);
  final User? _user;

  @override
  Future<User?> build() async => _user;

  @override
  Future<void> logout() async {}
}

class _TestPushService extends PushService {
  _TestPushService(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;

  @override
  Future<void> toggle(bool v) async => state = v;
}

ProviderContainer createContainer({
  User? user,
  bool pushEnabled = false,
}) {
  return ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(() => _TestAuthController(user)),
      pushServiceProvider.overrideWith(() => _TestPushService(pushEnabled)),
      syncStateProvider.overrideWith(() => SyncStateNotifier()),
    ],
  );
}

Widget buildApp(Widget child, {required ProviderContainer container}) {
  final router = GoRouter(
    initialLocation: AppRoutes.settings,
    routes: [
      GoRoute(path: AppRoutes.settings, builder: (_, _) => child),
      GoRoute(
        path: AppRoutes.soul,
        builder: (_, _) => const Scaffold(body: Text('soul-stub')),
      ),
      GoRoute(
        path: AppRoutes.contexts,
        builder: (_, _) => const Scaffold(body: Text('contexts-stub')),
      ),
      GoRoute(
        path: AppRoutes.telegram,
        builder: (_, _) => const Scaffold(body: Text('telegram-stub')),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
    ),
  );
}

void main() {
  group('SettingsScreen', () {
    testWidgets('renders title and sections', (tester) async {
      final container = createContainer(
        user: const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        buildApp(const SettingsScreen(), container: container),
      );
      await tester.pump();

      expect(find.text('Configurações'), findsWidgets);
      expect(find.text('CONTA'), findsOneWidget);
      expect(find.text('NOTIFICAÇÕES'), findsOneWidget);
      expect(find.text('AVANÇADO'), findsOneWidget);
    });

    testWidgets('shows user email and name', (tester) async {
      final container = createContainer(
        user: const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        buildApp(const SettingsScreen(), container: container),
      );
      await tester.pump();

      expect(find.text('a@b.com'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows fallback when user is null', (tester) async {
      final container = createContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        buildApp(const SettingsScreen(), container: container),
      );
      await tester.pump();

      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('renders push toggle', (tester) async {
      final container = createContainer(
        user: const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        buildApp(const SettingsScreen(), container: container),
      );
      await tester.pump();

      expect(find.text('Receber push'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('renders navigation tiles', (tester) async {
      final container = createContainer(
        user: const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        buildApp(const SettingsScreen(), container: container),
      );
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Dados'), 100);

      expect(find.text('Personalidade do agent'), findsOneWidget);
      expect(find.text('Contextos'), findsOneWidget);
      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text('Dados'), findsOneWidget);
    });

    testWidgets('logout button opens confirmation dialog', (tester) async {
      final container = createContainer(
        user: const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        buildApp(const SettingsScreen(), container: container),
      );
      await tester.pump();
      await tester.tap(find.text('Sair da conta'));
      await tester.pump();

      expect(find.text('Sair da conta?'), findsOneWidget);
      expect(
        find.text(
          'Você precisará fazer login novamente para acessar suas notas.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('data tile opens sync dialog', (tester) async {
      final container = createContainer(
        user: const User(id: 'u-1', email: 'a@b.com', name: 'Alice'),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        buildApp(const SettingsScreen(), container: container),
      );
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Dados'), 100);
      await tester.pump();
      await tester.drag(find.byType(Scrollable), const Offset(0, -50));
      await tester.pump();
      await tester.tap(find.text('Dados'));
      await tester.pump();

      expect(find.text('Sincronização'), findsOneWidget);
      expect(
        find.text('Nenhuma sincronização registrada.'),
        findsOneWidget,
      );
    });
  });
}
