/// Screen that lists the user's contexts (folders) and lets them
/// create or delete entries.
///
/// The screen is online-only: contexts are loaded fresh from
/// `GET /contexts` on entry and after every mutation. A
/// [RefreshIndicator] re-runs the fetch on pull-to-refresh.
///
/// Mutations:
///   * **Create** — taps the FAB which shows
///     [_NewContextSheet], a bottom sheet with a single name field.
///     The slug is derived client-side from the name.
///   * **Delete** — swipe a row right-to-left to reveal a delete
///     intent, then confirm via the shared [showConfirmDialog].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/settings/data/settings_models.dart';
import 'package:supanotes/features/settings/data/settings_repository.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/confirm_dialog.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

/// Strings shown on the contexts screen.
class _ContextsStrings {
  _ContextsStrings._();

  static const String title = 'Contextos';
  static const String emptyTitle = 'Nenhum contexto ainda';
  static const String emptySubtitle =
      'Crie um contexto para agrupar notas relacionadas.';
  static const String fabTooltip = 'Novo contexto';
  static const String retry = 'Tentar novamente';

  // Delete
  static const String deleteConfirmTitle = 'Apagar contexto?';
  static const String deleteConfirmMessage =
      'As notas vinculadas a este contexto perderão a referência.';
  static const String deleteConfirmLabel = 'Apagar';
  static const String deletedSnackbar = 'Contexto apagado.';

  // Bottom sheet
  static const String sheetTitle = 'Novo contexto';
  static const String sheetSubtitle =
      'Use um nome curto — exemplo: Trabalho, Pessoal, Estudos.';
  static const String sheetHint = 'Nome do contexto';
  static const String sheetCancel = 'Cancelar';
  static const String sheetCreate = 'Criar';
  static const String sheetCreating = 'Criando…';
  static const String sheetEmptyError = 'Digite um nome.';
  static const String createdSnackbar = 'Contexto criado.';
}

/// Async loader for the user's contexts.
///
/// Defined here (and not in `core/di/providers.dart`) because it is
/// only consumed by this feature and the screen needs an easy way to
/// invalidate it after every mutation.
final contextsListProvider = FutureProvider<List<UserContext>>((ref) {
  return ref.watch(settingsRepositoryProvider).getContexts();
});

class ContextsScreen extends ConsumerWidget {
  const ContextsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(contextsListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(_ContextsStrings.title)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(contextsListProvider);
          await ref.read(contextsListProvider.future);
        },
        child: async.when(
          data: (contexts) => _ContextsList(contexts: contexts),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorView(
            message: err is ApiException ? err.message : err.toString(),
            onRetry: () => ref.invalidate(contextsListProvider),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: _ContextsStrings.fabTooltip,
        onPressed: () => _showCreateSheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _NewContextSheet(),
    );
    if (created == true) {
      ref.invalidate(contextsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_ContextsStrings.createdSnackbar)),
        );
      }
    }
  }
}

class _ContextsList extends ConsumerWidget {
  const _ContextsList({required this.contexts});

  final List<UserContext> contexts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (contexts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.folder_open_outlined,
            title: _ContextsStrings.emptyTitle,
            subtitle: _ContextsStrings.emptySubtitle,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: contexts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final ctx = contexts[index];
        return Dismissible(
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
              tooltip: _ContextsStrings.deleteConfirmLabel,
              onPressed: () async {
                if (!await _confirmDelete(context)) return;
                if (!context.mounted) return;
                await _delete(context, ref, ctx.id);
              },
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context) {
    return showConfirmDialog(
      context: context,
      title: _ContextsStrings.deleteConfirmTitle,
      message: _ContextsStrings.deleteConfirmMessage,
      confirmLabel: _ContextsStrings.deleteConfirmLabel,
      destructive: true,
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    try {
      await ref.read(settingsRepositoryProvider).deleteContext(id);
      ref.invalidate(contextsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_ContextsStrings.deletedSnackbar)),
        );
      }
    } on ApiException catch (e) {
      // Re-fetch so the dismissed row reappears.
      ref.invalidate(contextsListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text(_ContextsStrings.retry),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NewContextSheet extends ConsumerStatefulWidget {
  const _NewContextSheet();

  @override
  ConsumerState<_NewContextSheet> createState() => _NewContextSheetState();
}

class _NewContextSheetState extends ConsumerState<_NewContextSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = _ContextsStrings.sheetEmptyError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(settingsRepositoryProvider).createContext(name);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg + viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _ContextsStrings.sheetTitle,
            style: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _ContextsStrings.sheetSubtitle,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: _ContextsStrings.sheetHint,
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text(_ContextsStrings.sheetCancel),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(
                    _submitting
                        ? _ContextsStrings.sheetCreating
                        : _ContextsStrings.sheetCreate,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
