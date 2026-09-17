import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/constants/app_constants.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_link_provider.dart';
import 'package:supanotes/core/router/app_router.dart';
import 'package:supanotes/core/sync/note_remote_sync_runtime.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/share/application/share_intake_coordinator.dart';
import 'package:supanotes/features/notes/share/domain/share_strings.dart';
import 'package:supanotes/features/notes/share/presentation/note_picker_sheet.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/expressive_snack/expressive_snack.dart';

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
      unawaited(
        coordinator.onAuthStateChanged(
          ref.read(authControllerProvider).asData?.value,
        ),
      );
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
      unawaited(_handleAppResumed());
    }
  }

  Future<void> _handleAppResumed() async {
    final taskWorker = ref.read(taskOutboxWorkerProvider);
    taskWorker?.wake();
    try {
      // Task snapshots must reach the server before the note feed can apply
      // remote changes that may include the same task.
      await taskWorker?.drain();
    } on Object catch (error, stackTrace) {
      // A transient local/transport failure must not keep note sync paused.
      debugPrint('Task outbox foreground drain failed: $error\n$stackTrace');
    }
    if (!mounted) return;

    ref.read(noteOutboxWorkerProvider)?.wake();
    ref.read(noteRemoteSyncCoordinatorProvider)?.wake();
    final coordinator = ref.read(shareIntakeCoordinatorProvider);
    final notes = ref.read(activeNotesProvider).asData?.value;
    if (notes != null && notes.isNotEmpty) {
      unawaited(coordinator.publishNotesIndex(notes));
    }
    unawaited(_processPendingShare());
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
    ref.watch(taskOutboxRuntimeProvider);
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
        if (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS) {
          final brightness = MediaQuery.platformBrightnessOf(context);
          final themeData = brightness == Brightness.dark
              ? AppTheme.darkTheme
              : AppTheme.lightTheme;
          result = Theme(data: themeData, child: result);
          final cupertinoTheme = brightness == Brightness.dark
              ? AppTheme.cupertinoDarkTheme
              : AppTheme.cupertinoLightTheme;
          result = CupertinoTheme(data: cupertinoTheme, child: result);
        }
        result = SnackOverlay(child: result);
        return result;
      },
    );
  }
}
