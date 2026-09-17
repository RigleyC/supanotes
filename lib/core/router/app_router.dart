import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:cupertino_native_better/utils/transition_observer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/core/router/auth_guard.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/login_screen.dart';
import 'package:supanotes/features/auth/presentation/register_screen.dart';
import 'package:supanotes/features/auth/presentation/splash_screen.dart';
import 'package:supanotes/features/notes/attachments/data/authenticated_attachment_delivery.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_delivery.dart';
import 'package:supanotes/features/notes/catalog/presentation/notes_list_screen.dart';
import 'package:supanotes/features/notes/editor/presentation/note_editor_screen.dart';
import 'package:supanotes/features/notes/sharing/presentation/share_link_access_screen.dart';
import 'package:supanotes/features/settings/presentation/mcp_screen.dart';
import 'package:supanotes/features/settings/presentation/settings_screen.dart';
import 'package:supanotes/features/tasks/presentation/completed_tasks_screen.dart';
import 'package:supanotes/features/tasks/presentation/task_editor_screen.dart';
import 'package:supanotes/features/tasks/presentation/tasks_screen.dart';
import 'package:supanotes/shared/widgets/app_navigation_shell.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

List<NavigatorObserver> _appNavigatorObservers() {
  final observers = <NavigatorObserver>[CNTabBarRouteObserver()];
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    observers.add(CNTransitionObserver());
  }
  return observers;
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AsyncValue<User?>>(
    ref.read(authControllerProvider),
  );
  ref.listen<AsyncValue<User?>>(
    authControllerProvider,
    (_, next) => notifier.value = next,
  );
  ref.onDispose(notifier.dispose);

  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    observers: _appNavigatorObservers(),
    refreshListenable: notifier,
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        redirect: (_, _) => AppRoutes.tasks,
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(path: AppRoutes.mcp, builder: (_, _) => const McpScreen()),
      GoRoute(
        path: AppRoutes.shareLink,
        builder: (_, state) =>
            ShareLinkAccessScreen(token: state.pathParameters['token']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) => AppNavigationShell(
          navigationShell: navigationShell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tasks,
                builder: (_, _) => const TasksScreen(),
                routes: [
                  GoRoute(
                    path: 'completed',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const CompletedTasksScreen(),
                  ),
                  GoRoute(
                    path: 'standalone',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, _) => const TaskEditorScreen(),
                  ),
                  GoRoute(
                    path: 'standalone/:id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) => TaskEditorScreen(
                      taskId: state.pathParameters['id'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.notes,
                builder: (_, _) => const NotesListScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (_, state) {
                      return NoteEditorScreen(
                        noteId: state.pathParameters['id']!,
                        blockId: state.uri.queryParameters['blockId'],
                        attachmentDelivery: AuthenticatedAttachmentDelivery(
                          ref.read(apiClientProvider),
                          preference: AttachmentDeliveryPreference.localFirst,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final result = authGuardRedirect(
        currentLocation: state.matchedLocation,
        authState: notifier.value,
      );
      return result;
    },
  );

  return router;
});
