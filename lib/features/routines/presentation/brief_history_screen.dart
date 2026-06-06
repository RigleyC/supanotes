import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_spacing.dart';
import '../../../shared/widgets/error_snackbar.dart';
import '../data/routines_repository.dart';
import '../domain/routine_log_model.dart';
import 'widgets/brief_log_tile.dart';

/// Async load of the most recent brief execution logs. The backend
/// returns at most 50 rows ordered most-recent-first; the UI mirrors
/// that ordering verbatim.
final routineLogsProvider = FutureProvider<List<RoutineLogModel>>((ref) {
  return ref.watch(routinesRepositoryProvider).getLogs();
});

class BriefHistoryScreen extends ConsumerWidget {
  const BriefHistoryScreen({super.key});

  static const _appBarTitle = 'Histórico de briefs';
  static const _emptyTitle = 'Nenhum brief executado ainda';
  static const _emptySubtitle =
      'Os resultados gerados pelas suas rotinas aparecerão aqui.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(routineLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(_appBarTitle),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(routineLogsProvider),
        child: logsAsync.when(
          data: (logs) => _Body(logs: logs),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorView(
            message: '$err',
            onRetry: () => ref.invalidate(routineLogsProvider),
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
          message: 'Falha ao carregar histórico: $message',
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
