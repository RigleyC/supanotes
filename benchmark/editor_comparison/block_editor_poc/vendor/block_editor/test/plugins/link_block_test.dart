import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

BlockNode linkNode({String url = '', String displayText = ''}) {
  return BlockNode(
    type: BlockTypes.link,
    attributes: {
      if (url.isNotEmpty) 'url': url,
      if (displayText.isNotEmpty) 'displayText': displayText,
    },
  );
}

void main() {
  group('LinkBlock — plugin contract', () {
    test('blockType is link', () {
      expect(LinkBlock().blockType, BlockTypes.link);
    });

    test('serialize round-trips via toJson', () {
      final node = linkNode(url: 'https://example.com');
      final json = LinkBlock().serialize(node);
      expect(json['type'], BlockTypes.link);
    });

    test('deserialize produces correct type', () {
      final node = linkNode(url: 'https://example.com');
      final json = LinkBlock().serialize(node);
      final restored = LinkBlock().deserialize(json);
      expect(restored.type, BlockTypes.link);
    });

    test('slashCommandItem label is Link', () {
      expect(LinkBlock().slashCommandItem().label, 'Link');
    });

    test('slashCommandGroup is Basic', () {
      expect(LinkBlock().slashCommandGroup(), 'Basic');
    });
  });

  group('LinkBlock — rendering', () {
    testWidgets('renders placeholder when url is absent', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return LinkBlock().build(
                    linkNode(),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('No URL'), findsOneWidget);
    });

    testWidgets('renders displayText when provided', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return LinkBlock().build(
                    linkNode(
                      url: 'https://example.com',
                      displayText: 'Visit example',
                    ),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Visit example'), findsOneWidget);
    });

    testWidgets('falls back to url as displayText when displayText absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return LinkBlock().build(
                    linkNode(url: 'https://example.com'),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('https://example.com'), findsOneWidget);
    });

    testWidgets('emits link_open_requested on tap when no config callback', (
      tester,
    ) async {
      BlockEvent? received;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return LinkBlock().build(
                    linkNode(url: 'https://example.com'),
                    EditorSelection.none,
                    (e) => received = e,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      expect(received, isA<CustomBlockEvent>());
      final event = received as CustomBlockEvent;
      expect(event.eventType, 'link_open_requested');
      expect(event.payload, 'https://example.com');
    });

    testWidgets('calls onOpen callback when provided', (tester) async {
      String? openedUrl;
      BlockEvent? received;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              linkConfig: LinkBlockConfig(
                onOpen: (url) async => openedUrl = url,
              ),
              child: Builder(
                builder: (context) {
                  return LinkBlock().build(
                    linkNode(url: 'https://example.com'),
                    EditorSelection.none,
                    (e) => received = e,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      expect(openedUrl, 'https://example.com');
      expect(received, isNull);
    });

    testWidgets('shows url as subtext when displayText differs from url', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return LinkBlock().build(
                    linkNode(
                      url: 'https://example.com',
                      displayText: 'Example',
                    ),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);
    });

    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return LinkBlock().build(
                    linkNode(url: 'https://example.com'),
                    EditorSelection.none,
                    (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
