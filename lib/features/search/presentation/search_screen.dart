/// Search screen — single-route entry point for the `/search` location.
///
/// Holds three pieces of ephemeral state in [State]: the debounced
/// query string, the active [SearchMode], and the in-flight
/// `Future<List<SearchResultModel>>`. Whenever the query *or* the mode
/// changes the future is rebuilt with a fresh repository call and the
/// [FutureBuilder] re-renders. We deliberately do **not** push this
/// state into Riverpod because it is purely transient and would only
/// add ceremony.
///
/// Three idle states are exposed to the user:
///
///   * No query yet → `"Digite para buscar"` placeholder.
///   * Query in flight → skeleton placeholder cards.
///   * Query returned no hits → `"Nenhum resultado"` placeholder.
///
/// The screen is **online-only** (the repository goes through Dio with
/// no local fallback). Network / server failures surface as an
/// inline [EmptyState] with a retry action *and* a snack bar, so the
/// failure mode is hard to miss whichever direction the user is
/// looking.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/api/api_exceptions.dart';
import 'package:supanotes/features/search/data/search_repository.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/widgets/search_bar.dart';
import 'package:supanotes/features/search/presentation/widgets/search_mode_toggle.dart';
import 'package:supanotes/features/search/presentation/widgets/search_result_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';
import 'package:supanotes/shared/widgets/error_snackbar.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';
  SearchMode _mode = SearchMode.hybrid;
  Future<List<SearchResultModel>>? _resultsFuture;

  void _onQueryChanged(String query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _resultsFuture = _buildFuture();
    });
  }

  void _onModeChanged(SearchMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _resultsFuture = _buildFuture();
    });
  }

  void _retry() {
    setState(() {
      _resultsFuture = _buildFuture();
    });
  }

  /// Returns `null` when there is nothing to search for (so the screen
  /// can fall back to the "type to search" placeholder), otherwise
  /// fires a fresh request through the repository.
  Future<List<SearchResultModel>>? _buildFuture() {
    if (_query.isEmpty) return null;
    return ref
        .read(searchRepositoryProvider)
        .search(query: _query, mode: _mode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Voltar',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: SearchInputBar(onQueryChanged: _onQueryChanged),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SearchModeToggle(
                  value: _mode,
                  onChanged: _onModeChanged,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_resultsFuture == null) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Digite para buscar',
        subtitle: 'Resultados em tempo real conforme você digita.',
      );
    }

    return FutureBuilder<List<SearchResultModel>>(
      future: _resultsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SkeletonList();
        }

        if (snapshot.hasError) {
          final message = _messageFor(snapshot.error);
          // Surface a transient snack bar in addition to the inline
          // error so the failure is hard to miss whichever direction
          // the user happens to be looking.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showErrorSnackBar(context, message: message, onRetry: _retry);
          });
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'Erro na busca',
            subtitle: message,
            action: FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          );
        }

        final results = snapshot.data ?? const [];
        if (results.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'Nenhum resultado',
            subtitle: 'Tente outro termo ou outro modo de busca.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final result = results[index];
            return SearchResultTile(
              result: result,
              query: _query,
              onTap: () => context.push('/notes/${result.id}'),
            );
          },
        );
      },
    );
  }

  String _messageFor(Object? error) {
    if (error is ApiException) return error.message;
    if (error == null) return 'Erro desconhecido';
    return error.toString();
  }
}

/// Placeholder list rendered while the request is in flight.
///
/// Plain card-shaped grey blocks with a top [LinearProgressIndicator]
/// — no third-party shimmer library is in the pubspec and the design
/// system does not yet ship a token for animated skeletons, so a
/// static skeleton plus the progress bar is the minimum-friction
/// loading affordance.
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, __) => _SkeletonCard(scheme: scheme),
          ),
        ),
      ],
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final block = scheme.surfaceContainerHighest;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(block, widthFactor: 0.55, height: 16),
            const SizedBox(height: AppSpacing.sm),
            _bar(block, widthFactor: 0.95, height: 12),
            const SizedBox(height: AppSpacing.xs),
            _bar(block, widthFactor: 0.80, height: 12),
            const SizedBox(height: AppSpacing.sm),
            _bar(block, widthFactor: 0.20, height: 14),
          ],
        ),
      ),
    );
  }

  Widget _bar(Color color, {required double widthFactor, required double height}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
    );
  }
}
