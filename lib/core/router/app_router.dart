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
import 'package:supanotes/shared/widgets/app_navigation_shell.dart';

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
    initialLocation: AppRoutes.splash,
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
                builder: (_, _) => const _TasksRoutePlaceholder(),
                routes: [
                  GoRoute(
                    path: 'completed',
                    builder: (_, _) => const _CompletedTasksRoutePlaceholder(),
                  ),
                  GoRoute(
                    path: 'standalone',
                    builder: (_, _) => const _StandaloneTaskRoutePlaceholder(),
                  ),
                  GoRoute(
                    path: 'standalone/:id',
                    builder: (_, state) => _StandaloneTaskRoutePlaceholder(
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

class _TasksRoutePlaceholder extends StatelessWidget {
  const _TasksRoutePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Tasks')),
    );
  }
}

class _CompletedTasksRoutePlaceholder extends StatelessWidget {
  const _CompletedTasksRoutePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Concluídas')),
    );
  }
}

class _StandaloneTaskRoutePlaceholder extends StatelessWidget {
  const _StandaloneTaskRoutePlaceholder({this.taskId});

  final String? taskId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(taskId == null ? 'Nova task' : 'Task $taskId'),
      ),
    );
  }
}
