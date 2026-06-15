import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/search/presentation/widgets/search_loading_view.dart';

void main() {
  testWidgets('renders linear progress indicator', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SearchLoadingView(
          headerSlivers: [
            SliverAppBar(title: const Text('Search')),
          ],
        ),
      ),
    ));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
