import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/constants/app_constants.dart';
import 'core/di/providers.dart';
import 'shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_service.dart';
import 'features/auth/domain/user.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeTimeZones();
  
  try {
    final timeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZone.identifier));
  } catch (e) {
    debugPrint('Failed to get local timezone: $e');
  }

  final sharedPreferences = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPreferences),
    ],
  );

  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  await initializeDateFormatting('pt_BR', null);
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SupaNotesApp(),
    ),
  );

  // Permission is requested on first reminder intent by the notification
  // scheduler, not at app startup.
}

class SupaNotesApp extends ConsumerWidget {
  const SupaNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // We must listen to it (not just read) so Riverpod keeps it active and
    // forces it to rebuild when its internal dependencies (like auth) change.
    ref.listen(taskNotificationSchedulerProvider, (_, __) {});

    ref.listen<AsyncValue<User?>>(authControllerProvider, (prev, next) {
      next.when(
        data: (user) {
          if (user != null) {
            ref.read(syncServiceProvider)?.start();
          }
        },
        loading: () {},
        error: (_, _) {},
      );
    });

    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      routerConfig: router,
      scaffoldMessengerKey: AppMessenger.key,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      builder: (context, child) {
        Widget result = child!;
        if (PlatformInfo.isIOS) {
          final brightness = MediaQuery.platformBrightnessOf(context);
          final themeData = brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme;
          result = Theme(
            data: themeData,
            child: result,
          );
        }
        result = SnackOverlay(child: result);
        return result;
      },
    );
  }
}
