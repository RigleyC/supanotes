import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/features/settings/presentation/controllers/contexts_controller.dart';
import 'package:supanotes/features/settings/presentation/widgets/new_context_sheet.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/adaptive_sliver_nav_bar.dart';
import 'package:supanotes/shared/widgets/app_bottom_sheet.dart';
import 'package:supanotes/shared/widgets/app_error_view.dart';
import 'package:supanotes/shared/widgets/app_snackbar.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

class ContextsScreen extends ConsumerWidget {
  const ContextsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contextsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(contextsProvider),
        child: CustomScrollView(
          slivers: [
            const AdaptiveSliverNavBar(title: Text('Contextos')),
            async.when(
              data: (contexts) => _ContextsList(contexts: contexts),
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                child: AppErrorView(
                  title: err is ApiException ? err.message : err.toString(),
                  onRetry: () => ref.invalidate(contextsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Novo contexto',
        onPressed: () => _showCreateSheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final created = await showAppBottomSheet<bool>(
      context: context,
      builder: (_) => const NewContextSheet(),
    );
    if (created == true && context.mounted) {
      AppMessenger.showSuccess(context, 'Contexto criado.');
    }
  }
}

class _ContextsList extends ConsumerWidget {
  const _ContextsList({required this.contexts});

  final List<UserContext> contexts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (contexts.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            EmptyState(
              icon: Icons.folder_open_outlined,
              title: 'Nenhum contexto ainda',
              subtitle: 'Crie um contexto para agrupar notas relacionadas.',
            ),
          ],
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final ctx = contexts[index];
          return Column(
            children: [
              if (index > 0) const Divider(height: 1),
              Dismissible(
                key: ValueKey(ctx.id),
                direction: DismissDirection.endToStart,
                background: _DismissBackground(),
                confirmDismiss: (_) => _confirmDelete(context),
                onDismissed: (_) => _delete(context, ref, ctx.id),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(ctx.name),
                  subtitle: Text(ctx.slug),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Apagar',
                    onPressed: () async {
                      if (!await _confirmDelete(context)) return;
                      if (!context.mounted) return;
                      await _delete(context, ref, ctx.id);
                    },
                  ),
                ),
              ),
            ],
          );
        },
        childCount: contexts.length,
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) {
    return showConfirmDialog(
      context: context,
      title: 'Apagar contexto?',
      message: 'As notas vinculadas a este contexto perderão a referência.',
      confirmLabel: 'Apagar',
      destructive: true,
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(settingsRepositoryProvider).deleteContext(id);
      ref.invalidate(contextsProvider);
      if (context.mounted) {
        AppMessenger.showSuccess(context, 'Contexto apagado.');
      }
    } on ApiException catch (e) {
      ref.invalidate(contextsProvider);
      if (context.mounted) {
        AppMessenger.showError(context, e.message);
      }
    }
  }
}

class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.error,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Icon(Icons.delete_outline, color: scheme.onError),
    );
  }
}
