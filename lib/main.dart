import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/app/supa_notes_app.dart';
import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:timezone/data/latest.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopPlatform()) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(360, 480),
      center: true,
      title: AppConstants.appName,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  initializeTimeZones();

  try {
    final timeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZone.identifier));
  } catch (e) {
    debugPrint('Failed to get local timezone: $e');
  }

  final sharedPreferences = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(sharedPreferences)],
  );

  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  await initializeDateFormatting('pt_BR');
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SupaNotesApp(),
    ),
  );

  // Permission is requested on first reminder intent by the notification
  // scheduler, not at app startup.
}
