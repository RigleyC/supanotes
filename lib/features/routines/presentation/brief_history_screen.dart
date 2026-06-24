import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/adaptive_sliver_nav_bar.dart';
import '../../../shared/widgets/app_error_view.dart';
import '../domain/routine_log_model.dart';
import 'controllers/brief_history_controller.dart';
import 'widgets/brief_log_tile.dart';

class BriefHistoryScreen extends ConsumerWidget {
  const BriefHistoryScreen({super.key});

  static const _appBarTitle = 'Histórico de briefs';
  static const _emptyTitle = 'Nenhum brief executado ainda';
  static const _emptySubtitle =
      'Os resultados gerados pelas suas rotinas aparecerão aqui.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(briefHistoryProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(briefHistoryProvider),
        child: CustomScrollView(
          slivers: [
            const AdaptiveSliverNavBar(title: Text(_appBarTitle)),
            logsAsync.when(
              data: (logs) => _Body(logs: logs),
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                child: AppErrorView(
                  title: '$err',
                  onRetry: () => ref.invalidate(briefHistoryProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.logs});

  final List<RoutineLogModel> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        sliver: SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            children: [
              const SizedBox(height: 80),
              Icon(Icons.history_toggle_off,
                  size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: AppSpacing.md),
              const Text(
                BriefHistoryScreen._emptyTitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                BriefHistoryScreen._emptySubtitle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              BriefLogTile(log: logs[index]),
            ],
          );
        },
        childCount: logs.length,
      ),
    );
  }
}
