import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/widgets/search_results_view.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

Widget buildTest({
  required String query,
  required List<SearchResultModel> results,
  ValueChanged<SearchResultModel>? onTap,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SearchResultsView(
        headerSlivers: [
          SliverAppBar(title: const Text('Search')),
        ],
        query: query,
        results: results,
        onTap: onTap ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('SearchResultsView', () {
    testWidgets('shows empty state when no results', (tester) async {
      await tester.pumpWidget(buildTest(query: 'test', results: const []));
      expect(find.text('Nenhum resultado'), findsOneWidget);
      expect(find.text('Tente outro termo.'), findsOneWidget);
    });

    testWidgets('renders list of results', (tester) async {
      final results = [
        SearchResultModel(id: '1', title: 'Note 1', excerpt: '...', score: 0.9),
        SearchResultModel(id: '2', title: 'Note 2', excerpt: '...', score: 0.8),
      ];
      await tester.pumpWidget(buildTest(query: 'note', results: results));
      expect(find.text('Note 1'), findsOneWidget);
      expect(find.text('Note 2'), findsOneWidget);
    });

    testWidgets('fires onTap when a result is tapped', (tester) async {
      SearchResultModel? tapped;
      final results = [
        SearchResultModel(id: '1', title: 'Note 1', excerpt: '...', score: 0.9),
      ];
      await tester.pumpWidget(
        buildTest(
          query: 'note',
          results: results,
          onTap: (r) => tapped = r,
        ),
      );
      await tester.tap(find.text('Note 1'));
      expect(tapped?.id, '1');
    });
  });
}
