import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

BlockNode fileNode({
  String filename = 'report.pdf',
  String size = '1.2 MB',
  String path = '/tmp/report.pdf',
}) {
  return BlockNode(
    type: BlockTypes.file,
    attributes: {'filename': filename, 'size': size, 'path': path},
  );
}

void main() {
  group('FileBlock — plugin contract', () {
    test('blockType is file', () {
      expect(FileBlock().blockType, BlockTypes.file);
    });

    test('serialize round-trips via toJson', () {
      final node = fileNode();
      final json = FileBlock().serialize(node);
      expect(json['type'], BlockTypes.file);
    });

    test('deserialize produces correct type', () {
      final node = fileNode();
      final json = FileBlock().serialize(node);
      final restored = FileBlock().deserialize(json);
      expect(restored.type, BlockTypes.file);
    });

    test('slashCommandItem label is File', () {
      expect(FileBlock().slashCommandItem().label, 'File');
    });

    test('slashCommandGroup is Media', () {
      expect(FileBlock().slashCommandGroup(), 'Media');
    });
  });

  group('FileBlock — rendering', () {
    testWidgets('renders filename', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return FileBlock().build(
                  fileNode(filename: 'document.pdf'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('document.pdf'), findsOneWidget);
    });

    testWidgets('renders file size', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return FileBlock().build(
                  fileNode(size: '3.7 MB'),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('3.7 MB'), findsOneWidget);
    });

    testWidgets('renders default filename when absent', (tester) async {
      await tester.pumpWidget(
        wrap(
          BlockEditorScope(
            child: Builder(
              builder: (context) {
                return FileBlock().build(
                  BlockNode(type: BlockTypes.file),
                  EditorSelection.none,
                  (_) {},
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('Untitled file'), findsOneWidget);
    });

    testWidgets(
      'emits file_download_requested when download tapped and no config callback',
      (tester) async {
        BlockEvent? received;
        await tester.pumpWidget(
          wrap(
            SizedBox(
              width: 400,
              child: BlockEditorScope(
                child: Builder(
                  builder: (context) {
                    return FileBlock().build(
                      fileNode(path: '/tmp/report.pdf'),
                      EditorSelection.none,
                      (e) => received = e,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(GestureDetector).first);
        expect(received, isA<CustomBlockEvent>());
        final event = received as CustomBlockEvent;
        expect(event.eventType, 'file_download_requested');
        expect(event.payload, '/tmp/report.pdf');
      },
    );

    testWidgets(
      'emits file_open_requested when open tapped and no config callback',
      (tester) async {
        BlockEvent? received;
        await tester.pumpWidget(
          wrap(
            SizedBox(
              width: 400,
              child: BlockEditorScope(
                child: Builder(
                  builder: (context) {
                    return FileBlock().build(
                      fileNode(path: '/tmp/report.pdf'),
                      EditorSelection.none,
                      (e) => received = e,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(GestureDetector).last);
        expect(received, isA<CustomBlockEvent>());
        final event = received as CustomBlockEvent;
        expect(event.eventType, 'file_open_requested');
      },
    );

    testWidgets('calls onDownload callback when provided', (tester) async {
      String? downloadedPath;
      BlockEvent? received;
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              fileConfig: FileBlockConfig(
                onDownload: (path) async => downloadedPath = path,
              ),
              child: Builder(
                builder: (context) {
                  return FileBlock().build(
                    fileNode(path: '/tmp/report.pdf'),
                    EditorSelection.none,
                    (e) => received = e,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(GestureDetector).first);
      expect(downloadedPath, '/tmp/report.pdf');
      expect(received, isNull);
    });

    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 400,
            child: BlockEditorScope(
              child: Builder(
                builder: (context) {
                  return FileBlock().build(
                    fileNode(),
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
