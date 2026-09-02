import 'dart:async';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_link_provider.dart';
import 'package:supanotes/core/router/app_router.dart';
import 'package:supanotes/core/sync/note_remote_sync_runtime.dart';
import 'package:supanotes/core/utils/platform_utils.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/share/application/share_intake_coordinator.dart';
import 'package:supanotes/features/notes/share/domain/share_strings.dart';
import 'package:supanotes/features/notes/share/presentation/note_picker_sheet.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';
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

class SupaNotesApp extends ConsumerStatefulWidget {
  const SupaNotesApp({super.key});

  @override
  ConsumerState<SupaNotesApp> createState() => _SupaNotesAppState();
}

class _SupaNotesAppState extends ConsumerState<SupaNotesApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinator = ref.read(shareIntakeCoordinatorProvider);
      unawaited(coordinator.onAuthStateChanged(
        ref.read(authControllerProvider).asData?.value,
      ));
      final notes = ref.read(activeNotesProvider).asData?.value;
      if (notes != null && notes.isNotEmpty) {
        unawaited(coordinator.publishNotesIndex(notes));
      }
      unawaited(_processPendingShare());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(noteOutboxWorkerProvider)?.wake();
      ref.read(noteRemoteSyncCoordinatorProvider)?.wake();
      final coordinator = ref.read(shareIntakeCoordinatorProvider);
      final notes = ref.read(activeNotesProvider).asData?.value;
      if (notes != null && notes.isNotEmpty) {
        unawaited(coordinator.publishNotesIndex(notes));
      }
      unawaited(_processPendingShare());
    }
  }

  Future<void> _processPendingShare() async {
    final PendingShareResult result;
    try {
      result = await ref
          .read(shareIntakeCoordinatorProvider)
          .processPendingShare(pickNote: _pickNote);
    } catch (error) {
      debugPrint('Pending shared link delivery failed: $error');
      AppMessenger.showError(ShareStrings.deliveryFailed);
      return;
    }
    if (!mounted) return;
    switch (result) {
      case PendingShareDelivered(:final note):
        AppMessenger.showSuccess(ShareStrings.linkSavedIn(note.title));
      case PendingShareInvalidUrl():
        AppMessenger.showInfo(ShareStrings.sharedTextHasNoUrl);
      case PendingShareNone() || PendingShareDismissed():
        break;
    }
  }

  Future<NoteModel?> _pickNote(List<NoteModel> notes) {
    if (!mounted) return Future.value();
    return showShareNotePickerSheet(context, notes: notes);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(noteOutboxRuntimeProvider);
    ref.listen(taskNotificationSchedulerProvider, (_, _) {});
    ref.listen(authControllerProvider, (_, next) {
      // Ignore loading/error transitions: only settled sessions drive the
      // native bridge and pending-share delivery.
      next.whenData((user) {
        final coordinator = ref.read(shareIntakeCoordinatorProvider);
        unawaited(coordinator.onAuthStateChanged(user));
        if (user != null) unawaited(_processPendingShare());
      });
    });
    ref.listen(noteRemoteSyncRuntimeProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) {
          debugPrint('Incremental note sync failed: $error');
        },
      );
    });
    ref.listen(activeNotesProvider, (_, next) {
      next.whenData((notes) {
        unawaited(
          ref.read(shareIntakeCoordinatorProvider).publishNotesIndex(notes),
        );
      });
    });

    final router = ref.watch(goRouterProvider);
    ref.listen(appLinkProvider, (_, next) {
      next.whenData((uri) {
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 's') {
          router.go(uri.path);
        }
      });
    });

    return MaterialApp.router(
      title: AppConstants.appName,
      routerConfig: router,
      scaffoldMessengerKey: AppMessenger.key,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      builder: (context, child) {
        var result = child!;
        if (PlatformInfo.isIOS) {
          final brightness = MediaQuery.platformBrightnessOf(context);
          final themeData = brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme;
          result = Theme(data: themeData, child: result);
        }
        result = SnackOverlay(child: result);
        return result;
      },
    );
  }
}
