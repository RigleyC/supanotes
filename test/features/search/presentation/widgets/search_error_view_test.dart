import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/search/presentation/widgets/search_error_view.dart';

void main() {
  testWidgets('renders error state with message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchErrorView(
          headerSlivers: [
            SliverAppBar(title: const Text('Search')),
          ],
          error: 'Network error',
        ),
      ),
    ));
    expect(find.text('Erro na busca'), findsOneWidget);
    expect(find.text('Network error'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });
}
