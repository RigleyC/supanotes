import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

BlockNode imageNode({
  String source = 'network',
  String url = '',
  String path = '',
}) {
  return BlockNode(
    type: BlockTypes.image,
    attributes: {
      'source': source,
      if (url.isNotEmpty) 'url': url,
      if (path.isNotEmpty) 'path': path,
    },
  );
}

void main() {
  group('ImageBlock — plugin contract', () {
    test('blockType is image', () {
      expect(ImageBlock().blockType, BlockTypes.image);
    });

    test('serialize round-trips via toJson', () {
      final node = imageNode(
        source: 'network',
        url: 'https://example.com/img.png',
      );
      final json = ImageBlock().serialize(node);
      expect(json['type'], BlockTypes.image);
    });

    test('deserialize produces correct type', () {
      final node = imageNode();
      final json = ImageBlock().serialize(node);
      final restored = ImageBlock().deserialize(json);
      expect(restored.type, BlockTypes.image);
    });

    test('slashCommandItem label is Image', () {
      expect(ImageBlock().slashCommandItem().label, 'Image');
    });

    test('slashCommandGroup is Media', () {
      expect(ImageBlock().slashCommandGroup(), 'Media');
    });
  });

  group('ImageBlock — rendering', () {
    testWidgets('renders without error for network source with url', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return ImageBlock().build(
                  imageNode(
                    source: 'network',
                    url: 'https://example.com/img.png',
                  ),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders placeholder when network url is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return ImageBlock().build(
                  imageNode(source: 'network', url: ''),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('No image'), findsOneWidget);
    });

    testWidgets('renders loading widget for upload_pending source', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return ImageBlock().build(
                  imageNode(source: 'upload_pending'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('Loading…'), findsOneWidget);
    });

    testWidgets(
      'emits CustomBlockEvent with image_upload_requested for local source',
      (tester) async {
        BlockEvent? received;
        await tester.pumpWidget(
          wrap(
            BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return ImageBlock().build(
                    imageNode(source: 'local', path: '/tmp/photo.jpg'),
                    EditorSelection.none,
                    (e) => received = e,
                  );
                },
              ),
            ),
          ),
        );
        expect(received, isA<CustomBlockEvent>());
        final customEvent = received as CustomBlockEvent;
        expect(customEvent.eventType, 'image_upload_requested');
        expect(customEvent.payload, '/tmp/photo.jpg');
      },
    );

    testWidgets('custom onLoading builder is used when provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            imageConfig: ImageBlockConfig(
              onLoading: (ctx) => const Text('custom loading'),
            ),
            child: Builder(
              builder: (context) {
                return ImageBlock().build(
                  imageNode(source: 'upload_pending'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('custom loading'), findsOneWidget);
    });

    testWidgets('borderRadius is applied via ClipRRect', (tester) async {
      const radius = BorderRadius.all(Radius.circular(12));
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            imageConfig: const ImageBlockConfig(borderRadius: radius),
            child: Builder(
              builder: (context) {
                return ImageBlock().build(
                  imageNode(source: 'upload_pending'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, radius);
    });
  });
}
