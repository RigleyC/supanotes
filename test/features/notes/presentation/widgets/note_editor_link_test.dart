import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_link_tap_handler.dart';
import 'package:super_editor/super_editor.dart';

class _MockDocumentLayout extends Mock implements DocumentLayout {}

void main() {
  group('NoteEditor link suggestions', () {
    testWidgets('NoteLinkTapHandler extracts noteId from LinkAttribution', (
      tester,
    ) async {
      final uri = Uri.parse('note://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final document = MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'test-node',
            text: AttributedText(
              'Click here',
              AttributedSpans(
                attributions: [
                  SpanMarker(
                    attribution: LinkAttribution.fromUri(uri),
                    offset: 6,
                    markerType: SpanMarkerType.start,
                  ),
                  SpanMarker(
                    attribution: LinkAttribution.fromUri(uri),
                    offset: 10,
                    markerType: SpanMarkerType.end,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      final handler = NoteLinkTapHandler(document, onNoteTap: (_) {});

      const position = DocumentPosition(
        nodeId: 'test-node',
        nodePosition: TextNodePosition(offset: 8),
      );

      final cursor = handler.mouseCursorForContentHover(position);
      expect(cursor, isNotNull);
      expect(cursor, SystemMouseCursors.click);

      handler.dispose();
      document.dispose();
    });

    testWidgets('NoteLinkTapHandler opens external URLs on click', (
      tester,
    ) async {
      final uri = Uri.parse('https://example.com');
      final document = MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'test-node',
            text: AttributedText(
              'Click https://example.com',
              AttributedSpans(
                attributions: [
                  SpanMarker(
                    attribution: LinkAttribution.fromUri(uri),
                    offset: 6,
                    markerType: SpanMarkerType.start,
                  ),
                  SpanMarker(
                    attribution: LinkAttribution.fromUri(uri),
                    offset: 25,
                    markerType: SpanMarkerType.end,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      final handler = NoteLinkTapHandler(document, onNoteTap: (_) {});

      const position = DocumentPosition(
        nodeId: 'test-node',
        nodePosition: TextNodePosition(offset: 10),
      );

      final cursor = handler.mouseCursorForContentHover(position);
      expect(cursor, SystemMouseCursors.click);

      final layout = _MockDocumentLayout();
      when(
        () => layout.getDocumentPositionNearestToOffset(Offset.zero),
      ).thenReturn(
        const DocumentPosition(
          nodeId: 'test-node',
          nodePosition: TextNodePosition(offset: 10),
        ),
      );
      final result = handler.onTap(
        DocumentTapDetails(
          documentLayout: layout,
          layoutOffset: Offset.zero,
          globalOffset: Offset.zero,
        ),
      );
      expect(result, TapHandlingInstruction.halt);

      handler.dispose();
      document.dispose();
    });

    testWidgets('NoteLinkTapHandler triggers onNoteTap for note links', (
      tester,
    ) async {
      final uri = Uri.parse('note://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final document = MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'test-node',
            text: AttributedText(
              'Click here',
              AttributedSpans(
                attributions: [
                  SpanMarker(
                    attribution: LinkAttribution.fromUri(uri),
                    offset: 6,
                    markerType: SpanMarkerType.start,
                  ),
                  SpanMarker(
                    attribution: LinkAttribution.fromUri(uri),
                    offset: 10,
                    markerType: SpanMarkerType.end,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      String? tappedNoteId;
      final handler = NoteLinkTapHandler(
        document,
        onNoteTap: (noteId) => tappedNoteId = noteId,
      );

      final layout = _MockDocumentLayout();
      when(
        () => layout.getDocumentPositionNearestToOffset(Offset.zero),
      ).thenReturn(
        const DocumentPosition(
          nodeId: 'test-node',
          nodePosition: TextNodePosition(offset: 8),
        ),
      );

      final result = handler.onTap(
        DocumentTapDetails(
          documentLayout: layout,
          layoutOffset: Offset.zero,
          globalOffset: Offset.zero,
        ),
      );

      expect(result, TapHandlingInstruction.halt);
      expect(tappedNoteId, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');

      handler.dispose();
      document.dispose();
    });

    test('NoteLinkTapHandler leaves the caret after a stale link boundary', () {
      final uri = Uri.parse('note://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      final document = MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'test-node',
            text: AttributedText(
              'Click here',
              // Simulate a stale inclusive span that reaches the caret.
              AttributedSpans()..addAttribution(
                newAttribution: LinkAttribution.fromUri(uri),
                start: 6,
                end: 10,
              ),
            ),
          ),
        ],
      );
      final layout = _MockDocumentLayout();
      when(
        () => layout.getDocumentPositionNearestToOffset(Offset.zero),
      ).thenReturn(
        const DocumentPosition(
          nodeId: 'test-node',
          nodePosition: TextNodePosition(offset: 10),
        ),
      );
      final handler = NoteLinkTapHandler(document, onNoteTap: (_) {});

      final result = handler.onTap(
        DocumentTapDetails(
          documentLayout: layout,
          layoutOffset: Offset.zero,
          globalOffset: Offset.zero,
        ),
      );

      expect(result, TapHandlingInstruction.continueHandling);
      handler.dispose();
      document.dispose();
    });
  });
}
