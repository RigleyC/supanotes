import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:supanotes/core/app_version/app_version_provider.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/settings/presentation/settings_screen.dart';
import 'package:supanotes/shared/widgets/app_tile.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this.user);

  final User user;
  int logoutCalls = 0;

  @override
  Future<User?> build() async => user;

  @override
  Future<void> logout() async => logoutCalls++;
}

Widget _settingsApp(_StubAuthController controller) {
  final router = GoRouter(
    initialLocation: AppRoutes.settings,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.mcp,
        builder: (_, _) => const Scaffold(body: Text('MCP stub')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => controller),
      appPackageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'SupaNotes',
          packageName: 'com.example.supanotes',
          version: '1.3.0',
          buildNumber: '248',
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('renders a flat title-only account settings list', (
    tester,
  ) async {
    final controller = _StubAuthController(
      const User(id: 'u-1', name: 'Alice', email: 'alice@example.com'),
    );

    await tester.pumpWidget(_settingsApp(controller));
    await tester.pumpAndSettle();

    expect(tester.widget<AppBar>(find.byType(AppBar)).centerTitle, isTrue);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Nome'), findsNothing);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Conta'), findsNothing);
    expect(find.text('Avançado'), findsNothing);
    expect(find.text('Versão'), findsOneWidget);
    expect(find.text('1.3.0+248'), findsOneWidget);

    final tiles = tester.widgetList<AppTile>(find.byType(AppTile));
    expect(tiles, hasLength(5));
    expect(tiles.where((tile) => tile.subtitle != null), hasLength(1));
    final versionTile = tester.widget<AppTile>(
      find.widgetWithText(AppTile, 'Versão'),
    );
    expect(versionTile.onTap, isNull);
  });

  testWidgets('opens MCP from the settings list', (tester) async {
    final controller = _StubAuthController(
      const User(id: 'u-1', name: 'Alice', email: 'alice@example.com'),
    );

    await tester.pumpWidget(_settingsApp(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Protocolo de Contexto (MCP)'));
    await tester.pumpAndSettle();

    expect(find.text('MCP stub'), findsOneWidget);
  });

  testWidgets('confirms logout from the settings list', (tester) async {
    final controller = _StubAuthController(
      const User(id: 'u-1', name: 'Alice', email: 'alice@example.com'),
    );

    await tester.pumpWidget(_settingsApp(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sair da conta'));
    await tester.pumpAndSettle();
    expect(find.text('Sair da conta?'), findsOneWidget);

    await tester.tap(find.text('Sair').last);
    await tester.pumpAndSettle();

    expect(controller.logoutCalls, 1);
  });
}
