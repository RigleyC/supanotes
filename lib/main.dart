import 'package:cue/cue.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/api/backend_connectivity_hint.dart';
import 'firebase_options.dart';
import 'core/constants/app_constants.dart';
import 'core/di/providers.dart';
import 'core/router/app_router.dart';
import 'core/router/app_routes.dart';
import 'core/sync/sync_service.dart';
import 'features/auth/domain/user.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
  warnIfAndroidBackendUnreachable();
  runApp(const ProviderScope(child: SupaNotesApp()));
}

class SupaNotesApp extends ConsumerStatefulWidget {
  const SupaNotesApp({super.key});

  @override
  ConsumerState<SupaNotesApp> createState() => _SupaNotesAppState();
}

class _SupaNotesAppState extends ConsumerState<SupaNotesApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupFcmListeners());
  }

  void _setupFcmListeners() {
    FirebaseMessaging.onMessage.listen((message) {
      if (!mounted) return;
      if (message.notification != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message.notification!.title ?? '')),
        );
      }
    }, onError: (e) {
      debugPrint('FCM onMessage error: $e');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (!mounted) return;
      if (message.data['brief_type'] != null) {
        GoRouter.of(context).go(AppRoutes.routinesLogs);
      }
    }, onError: (e) {
      debugPrint('FCM onMessageOpenedApp error: $e');
    });
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
      builder: (context, child) {
        if (kDebugMode) {
          return CueDebugTools(child: child!);
        }
        return child!;
      },
    );
  }
}
