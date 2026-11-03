import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/attachment_renderers.dart';

void main() {
  Widget subject(RichLinkCard card) => MaterialApp(home: Scaffold(body: card));

  testWidgets('renders title, description and domain as compact text', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        RichLinkCard(
          url: 'https://example.com/post',
          title: 'Example',
          description: 'A safe link',
          domain: 'example.com',
        ),
      ),
    );

    expect(find.text('Example'), findsOneWidget);
    expect(find.text('A safe link'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('keeps the fallback URL when preview metadata is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(RichLinkCard(url: 'https://example.com/post')),
    );

    expect(find.text('https://example.com/post'), findsOneWidget);
  });

  testWidgets('renders an image slot on the left when image metadata exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        RichLinkCard(
          url: 'https://example.com/post',
          imageUrl: 'https://example.com/image.jpg',
          domain: 'example.com',
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
  });

  testWidgets('renders domain and url when previewStatus is failed', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        RichLinkCard(
          url: 'https://example.com/post',
          domain: 'example.com',
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('https://example.com/post'), findsOneWidget);
  });
}
