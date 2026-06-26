import 'package:cue/cue.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/shared/theme/app_theme.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/api/backend_connectivity_hint.dart';
import 'core/router/last_route_store.dart';
import 'firebase_options.dart';
import 'core/constants/app_constants.dart';
import 'core/di/providers.dart';
import 'shared/widgets/app_snackbar.dart';
import 'core/notifications/fcm_message_listeners.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_service.dart';
import 'features/auth/domain/user.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final sharedPreferences = await SharedPreferences.getInstance();

  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  warnIfAndroidBackendUnreachable();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const SupaNotesApp(),
    ),
  );
}

class SupaNotesApp extends ConsumerStatefulWidget {
  const SupaNotesApp({super.key});

  @override
  ConsumerState<SupaNotesApp> createState() => _SupaNotesAppState();
}

class _SupaNotesAppState extends ConsumerState<SupaNotesApp> {
  FcmMessageListeners? _fcmMessageListeners;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupFcmListeners());
  }

  void _setupFcmListeners() {
    if (!mounted) return;
    _fcmMessageListeners = FcmMessageListeners(context: context)..start();
  }

  @override
  void dispose() {
    _fcmMessageListeners?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      scaffoldMessengerKey: AppMessenger.key,
      builder: (context, child) {
        if (kDebugMode) {
          return CueDebugTools(child: child!);
        }
        return child!;
      },
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
    );
  }
}
