import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/features/search/presentation/widgets/search_result_tile.dart';
import 'package:supanotes/shared/theme/app_theme.dart';

void main() {
  final result = SearchResultModel(
    id: 'n-1',
    title: 'My Note',
    excerpt: 'some content here',
    score: 0.95,
  );

  Widget buildTest(SearchResultModel model, {VoidCallback? onTap}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SearchResultTile(
          result: model,
          query: 'content',
          onTap: onTap ?? () {},
        ),
      ),
    );
  }

  testWidgets('renders title and excerpt', (tester) async {
    await tester.pumpWidget(buildTest(result));
    expect(find.text('My Note'), findsOneWidget);
    expect(find.byType(RichText), findsAtLeastNWidgets(1));
  });

  testWidgets('renders fallback title when title is empty', (tester) async {
    final emptyTitle = SearchResultModel(
      id: 'n-2',
      title: '',
      excerpt: 'body text',
      score: 0.5,
    );
    await tester.pumpWidget(buildTest(emptyTitle));
    expect(find.text('Sem título'), findsOneWidget);
  });

  testWidgets('does not render excerpt section when excerpt is empty',
      (tester) async {
    final noExcerpt = SearchResultModel(
      id: 'n-3',
      title: 'Title Only',
      excerpt: '',
      score: 0.5,
    );
    await tester.pumpWidget(buildTest(noExcerpt));
    expect(find.text('Title Only'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('fires onTap when tapped', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(buildTest(result, onTap: () => tapped = true));
    await tester.tap(find.text('My Note'));
    expect(tapped, isTrue);
  });
}
