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
    final logsAsync = ref.watch(briefHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_appBarTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.read(briefHistoryControllerProvider.notifier).refresh(),
        child: logsAsync.when(
          data: (state) => _Body(logs: state.logs),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AppErrorView(
            title: '$err',
            onRetry: () =>
                ref.read(briefHistoryControllerProvider.notifier).refresh(),
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
        children: const [
          SizedBox(height: 80),
          Icon(Icons.history_toggle_off, size: 56, color: Colors.grey),
          SizedBox(height: AppSpacing.md),
          Text(
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
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return BriefLogTile(log: logs[index]);
      },
    );
  }
}
