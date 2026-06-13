import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_spacing.dart';
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
      appBar: AppBar(
        title: const Text(_appBarTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(briefHistoryProvider),
        child: logsAsync.when(
          data: (logs) => _Body(logs: logs),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AppErrorView(
            title: '$err',
            onRetry: () => ref.invalidate(briefHistoryProvider),
          ),
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
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
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: logs.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return BriefLogTile(log: logs[index]);
      },
    );
  }
}
