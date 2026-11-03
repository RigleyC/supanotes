import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

BlockNode youTubeNode({String videoId = ''}) {
  return BlockNode(
    type: BlockTypes.youtube,
    attributes: {if (videoId.isNotEmpty) 'videoId': videoId},
  );
}

void main() {
  group('YouTubeBlock — plugin contract', () {
    test('blockType is youtube', () {
      expect(YouTubeBlock().blockType, BlockTypes.youtube);
    });

    test('serialize round-trips via toJson', () {
      final node = youTubeNode(videoId: 'dQw4w9WgXcQ');
      final json = YouTubeBlock().serialize(node);
      expect(json['type'], BlockTypes.youtube);
    });

    test('deserialize produces correct type', () {
      final node = youTubeNode(videoId: 'dQw4w9WgXcQ');
      final json = YouTubeBlock().serialize(node);
      final restored = YouTubeBlock().deserialize(json);
      expect(restored.type, BlockTypes.youtube);
    });

    test('slashCommandItem label is YouTube', () {
      expect(YouTubeBlock().slashCommandItem().label, 'YouTube');
    });

    test('slashCommandGroup is Media', () {
      expect(YouTubeBlock().slashCommandGroup(), 'Media');
    });
  });

  group('YouTubeBlock — rendering', () {
    testWidgets('renders placeholder when videoId is absent', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return YouTubeBlock().build(
                  youTubeNode(),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('No video ID'), findsOneWidget);
    });

    testWidgets('renders preview when videoId is present', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return YouTubeBlock().build(
                  youTubeNode(videoId: 'dQw4w9WgXcQ'),
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

    testWidgets('emits youtube_play_requested on tap', (tester) async {
      BlockEvent? received;
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return YouTubeBlock().build(
                  youTubeNode(videoId: 'dQw4w9WgXcQ'),
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
      expect(event.eventType, 'youtube_play_requested');
      expect(event.payload, 'dQw4w9WgXcQ');
    });

    testWidgets('uses youtube-nocookie.com when privacyEnhanced is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            youTubeConfig: const YouTubeBlockConfig(privacyEnhanced: true),
            child: Builder(
              builder: (context) {
                return YouTubeBlock().build(
                  youTubeNode(videoId: 'abc123'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('youtube-nocookie.com'), findsOneWidget);
    });

    testWidgets('uses youtube.com when privacyEnhanced is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            youTubeConfig: const YouTubeBlockConfig(privacyEnhanced: false),
            child: Builder(
              builder: (context) {
                return YouTubeBlock().build(
                  youTubeNode(videoId: 'abc123'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('www.youtube.com'), findsOneWidget);
    });

    testWidgets('play button hidden when showControls is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            youTubeConfig: const YouTubeBlockConfig(showControls: false),
            child: Builder(
              builder: (context) {
                return YouTubeBlock().build(
                  youTubeNode(videoId: 'dQw4w9WgXcQ'),
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

    testWidgets('play button shown when showControls is true', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return YouTubeBlock().build(
                  youTubeNode(videoId: 'dQw4w9WgXcQ'),
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
  });
}
