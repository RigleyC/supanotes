import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/error_snackbar.dart';
import '../data/routines_repository.dart';
import '../domain/routine_model.dart';
import 'widgets/brief_schedule_card.dart';

/// Async load of the user's configured brief schedules.
///
/// The provider re-runs the HTTP call every time the ref is rebuilt
/// — fine for a settings-style screen that is rarely visible.
final routinesListProvider = FutureProvider<List<RoutineModel>>((ref) {
  return ref.watch(routinesRepositoryProvider).getRoutines();
});

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  static const _routeRoutinesLogs = '/routines/logs';

  static const _appBarTitle = 'Rotinas';
  static const _seeHistory = 'Ver histórico';
  static const _noRoutinesTitle = 'Nenhuma rotina cadastrada';
  static const _noRoutinesSubtitle =
      'Crie uma rotina no backend para começar a receber briefs.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(routinesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_appBarTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(routinesListProvider),
        child: routinesAsync.when(
          data: (routines) => _Body(
            routines: routines,
            onSeeHistory: () => context.push(_routeRoutinesLogs),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorView(
            message: '$err',
            onRetry: () => ref.invalidate(routinesListProvider),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.routines, required this.onSeeHistory});

  final List<RoutineModel> routines;
  final VoidCallback onSeeHistory;

  @override
  Widget build(BuildContext context) {
    if (routines.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [
          SizedBox(height: 80),
          Icon(
            Icons.event_note_outlined,
            size: 56,
            color: Colors.grey,
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            RoutinesScreen._noRoutinesTitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            RoutinesScreen._noRoutinesSubtitle,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final sorted = [...routines]
      ..sort((a, b) => a.briefType.index.compareTo(b.briefType.index));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        for (final routine in sorted) ...[
          BriefScheduleCard(routine: routine),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.sm),
        FilledButton.tonalIcon(
          onPressed: onSeeHistory,
          icon: const Icon(Icons.history),
          label: const Text(RoutinesScreen._seeHistory),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        showErrorSnackBar(
          context,
          message: 'Falha ao carregar rotinas: $message',
          onRetry: onRetry,
        );
      }
    });
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
