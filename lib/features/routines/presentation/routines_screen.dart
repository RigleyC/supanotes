import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_error_view.dart';
import '../domain/routine_model.dart';
import 'controllers/routines_controller.dart';
import 'widgets/brief_schedule_card.dart';

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  static const _appBarTitle = 'Rotinas';
  static const _seeHistory = 'Ver histórico';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(routinesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(_appBarTitle)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(routinesProvider),
        child: routinesAsync.when(
          data: (routines) => _Body(
            routines: routines,
            onSeeHistory: () => context.push(AppRoutes.routinesLogs),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AppErrorView(
            title: '$err',
            onRetry: () => ref.invalidate(routinesProvider),
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
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: 80),
              Icon(
                Icons.event_note_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Nenhuma rotina cadastrada',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Crie uma rotina no backend para começar a receber briefs.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
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
        Align(
          alignment: Alignment.centerLeft,
          child: IntrinsicWidth(
            child: AppButton(
              text: RoutinesScreen._seeHistory,
              variant: AppButtonVariant.tonal,
              icon: const Icon(Icons.history),
              onPressed: onSeeHistory,
            ),
          ),
        ),
      ],
    );
  }
}
