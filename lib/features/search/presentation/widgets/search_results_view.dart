library;

import 'package:flutter/material.dart';

import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/widgets/search_result_tile.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/empty_state.dart';

class SearchResultsView extends StatelessWidget {
  const SearchResultsView({
    super.key,
    required this.headerSlivers,
    required this.query,
    required this.results,
    required this.onTap,
  });

  final List<Widget> headerSlivers;
  final String query;
  final List<SearchResultModel> results;
  final ValueChanged<SearchResultModel> onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return CustomScrollView(
        slivers: [
          ...headerSlivers,
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off,
              title: 'Nenhum resultado',
              subtitle: 'Tente outro termo.',
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        ...headerSlivers,
        SliverPadding(
          padding: const EdgeInsets.all(AppSpacing.md),
          sliver: SliverList.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final result = results[index];
              return SearchResultTile(
                result: result,
                query: query,
                onTap: () => onTap(result),
              );
            },
          ),
        ),
      ],
    );
  }
}
