import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/constants/app_constants.dart';
import 'core/di/providers.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_service.dart';
import 'features/auth/domain/auth_state.dart';
import 'shared/theme/app_theme.dart';

void main() {
  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  runApp(const ProviderScope(child: SupaNotesApp()));
}

class SupaNotesApp extends ConsumerWidget {
  const SupaNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (prev, next) {
      final sync = ref.read(syncServiceProvider);
      next.when(
        data: (auth) {
          if (auth is AuthAuthenticated) {
            sync.start();
          } else if (auth is AuthUnauthenticated) {
            sync.dispose();
          }
        },
        loading: () {},
        error: (_, __) {},
      );
    });

    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
