library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:supanotes/core/router/app_routes.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/controllers/search_controller.dart';
import 'package:supanotes/features/search/presentation/widgets/search_bar.dart';
import 'package:supanotes/features/search/presentation/widgets/search_mode_toggle.dart';
import 'package:supanotes/features/search/presentation/widgets/search_result_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  void _onQueryChanged(String query) {
    setState(() => _query = query);
  }

  void _onModeChanged(SearchMode mode) {
    ref.read(searchModeProvider.notifier).set(mode);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(searchModeProvider);
    final searchAsync =
        ref.watch(searchResultsProvider((query: _query, mode: mode)));

    final results = searchAsync.asData?.value ?? const [];
    final isLoading = searchAsync.isLoading;
    final error = searchAsync.hasError
        ? searchAsync.error.toString()
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Voltar',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
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
                  value: mode,
                  onChanged: _onModeChanged,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(_query, results, isLoading, error)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    String query,
    List<SearchResultModel> results,
    bool isLoading,
    String? error,
  ) {
    if (query.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Digite para buscar',
        subtitle: 'Resultados em tempo real conforme você digita.',
      );
    }

    if (isLoading) {
      return const _SkeletonList();
    }

    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: 'Erro na busca',
        subtitle: error,
        action: FilledButton.icon(
          onPressed: () => _onQueryChanged(query),
          icon: const Icon(Icons.refresh),
          label: const Text('Tentar novamente'),
        ),
      );
    }

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
          query: query,
          onTap: () => context.push(AppRoutes.note(result.id)),
        );
      },
    );
  }
}

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

  Widget _bar(Color color,
      {required double widthFactor, required double height}) {
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
