import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

BlockNode videoNode({
  String source = 'network',
  String url = '',
  String path = '',
}) {
  return BlockNode(
    type: BlockTypes.video,
    attributes: {
      'source': source,
      if (url.isNotEmpty) 'url': url,
      if (path.isNotEmpty) 'path': path,
    },
  );
}

void main() {
  group('VideoBlock — plugin contract', () {
    test('blockType is video', () {
      expect(VideoBlock().blockType, BlockTypes.video);
    });

    test('serialize round-trips via toJson', () {
      final node = videoNode(
        source: 'network',
        url: 'https://example.com/v.mp4',
      );
      final json = VideoBlock().serialize(node);
      expect(json['type'], BlockTypes.video);
    });

    test('deserialize produces correct type', () {
      final node = videoNode();
      final json = VideoBlock().serialize(node);
      final restored = VideoBlock().deserialize(json);
      expect(restored.type, BlockTypes.video);
    });

    test('slashCommandItem label is Video', () {
      expect(VideoBlock().slashCommandItem().label, 'Video');
    });

    test('slashCommandGroup is Media', () {
      expect(VideoBlock().slashCommandGroup(), 'Media');
    });
  });

  group('VideoBlock — rendering', () {
    testWidgets('renders placeholder when url is empty', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return VideoBlock().build(
                  videoNode(source: 'network', url: ''),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('No video'), findsOneWidget);
    });

    testWidgets('renders preview container when url is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return VideoBlock().build(
                  videoNode(
                    source: 'network',
                    url: 'https://example.com/v.mp4',
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
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('emits video_play_requested on tap for network source', (
      tester,
    ) async {
      BlockEvent? received;
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return VideoBlock().build(
                  videoNode(
                    source: 'network',
                    url: 'https://example.com/v.mp4',
                  ),
                  EditorSelection.none,
                  (e) => received = e,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      expect(received, isA<CustomBlockEvent>());
      final event = received as CustomBlockEvent;
      expect(event.eventType, 'video_play_requested');
      expect(event.payload, 'https://example.com/v.mp4');
    });

    testWidgets('emits video_play_requested with path for local source', (
      tester,
    ) async {
      BlockEvent? received;
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return VideoBlock().build(
                  videoNode(source: 'local', path: '/tmp/video.mp4'),
                  EditorSelection.none,
                  (e) => received = e,
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector));
      final event = received as CustomBlockEvent;
      expect(event.payload, '/tmp/video.mp4');
    });

    testWidgets('play icon hidden when showControls is false', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            videoConfig: const VideoBlockConfig(showControls: false),
            child: Builder(
              builder: (context) {
                return VideoBlock().build(
                  videoNode(
                    source: 'network',
                    url: 'https://example.com/v.mp4',
                  ),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('play icon shown when showControls is true', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return VideoBlock().build(
                  videoNode(
                    source: 'network',
                    url: 'https://example.com/v.mp4',
                  ),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('renders without error for local source', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return VideoBlock().build(
                  videoNode(source: 'local', path: '/tmp/video.mp4'),
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
  });
}
