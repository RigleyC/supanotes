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
import 'core/router/app_link_provider.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/catalog/application/notes_providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/share/domain/share_note_index.dart';
import 'package:window_manager/window_manager.dart';
import 'core/utils/platform_utils.dart';

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

class SupaNotesApp extends ConsumerStatefulWidget {
  const SupaNotesApp({super.key});

  @override
  ConsumerState<SupaNotesApp> createState() => _SupaNotesAppState();
}

class _SupaNotesAppState extends ConsumerState<SupaNotesApp>
    with WidgetsBindingObserver {
  bool _processingPendingShare = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processPendingShare();
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
      _processPendingShare();
    }
  }

  Future<void> _publishIndex(List<NoteModel> notes) async {
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) return;
    try {
      await ref
          .read(nativeShareBridgeProvider)
          .publishNotesIndex(ShareNoteIndex.fromNotes(user.id, notes));
    } catch (error) {
      debugPrint('Error publishing native share index: $error');
    }
  }

  Future<void> _processPendingShare() async {
    if (_processingPendingShare || !mounted) return;
    final user = ref.read(authControllerProvider).asData?.value;
    if (user == null) return;
    _processingPendingShare = true;
    try {
      final bridge = ref.read(nativeShareBridgeProvider);
      final pending = await bridge.readPendingShare();
      final pendingText = pending?['text'] as String?;
      if (pendingText == null || pendingText.trim().isEmpty || !mounted) return;
      final delivery = ref.read(sharedLinkDeliveryProvider);
      final url = delivery.extractUrl(pendingText);
      if (url == null) {
        await bridge.clearPendingShare();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('O texto compartilhado não contém uma URL.'),
            ),
          );
        }
        return;
      }
      final notes = await ref.read(activeNotesProvider.future);
      if (!mounted) return;
      final targetNoteId = pending?['noteId'] as String?;
      NoteModel? note;
      if (targetNoteId == null || targetNoteId.isEmpty) {
        note = await showDialog<NoteModel>(
          context: context,
          builder: (_) => _ShareNotePicker(notes: notes),
        );
      } else {
        for (final candidate in notes) {
          if (candidate.id == targetNoteId) {
            note = candidate;
            break;
          }
        }
      }
      if (note == null) return;
      await delivery.appendToNote(noteId: note.id, url: url);
      await bridge.clearPendingShare();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Link salvo em ${note.title}')));
      }
    } catch (error) {
      debugPrint('Pending shared link delivery failed: $error');
    } finally {
      _processingPendingShare = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(taskNotificationSchedulerProvider, (_, _) {});
    ref.listen(authControllerProvider, (_, next) {
      if (next.asData?.value != null) {
        _processPendingShare();
      }
    });
    ref.listen(noteCatalogSyncProvider, (_, next) {
      next.whenOrNull(
        error: (error, _) {
          debugPrint('Note catalog sync failed: $error');
        },
      );
    });
    ref.listen(activeNotesProvider, (_, next) {
      next.whenData(_publishIndex);
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
        Widget result = child!;
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

class _ShareNotePicker extends StatefulWidget {
  const _ShareNotePicker({required this.notes});

  final List<NoteModel> notes;

  @override
  State<_ShareNotePicker> createState() => _ShareNotePickerState();
}

class _ShareNotePickerState extends State<_ShareNotePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final notes = widget.notes
        .where((note) => !note.isReadOnly)
        .where(
          (note) =>
              query.isEmpty ||
              note.title.toLowerCase().contains(query) ||
              (note.excerpt ?? note.content).toLowerCase().contains(query),
        )
        .toList(growable: false);
    return AlertDialog(
      title: const Text('Salvar link em'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar nota',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: notes.isEmpty
                  ? const Center(
                      child: Text('Nenhuma nota editável encontrada.'),
                    )
                  : ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return ListTile(
                          title: Text(
                            note.title.isEmpty ? 'Sem título' : note.title,
                          ),
                          subtitle: Text(
                            note.excerpt ?? note.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(context).pop(note),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
