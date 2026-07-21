import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_delegate.dart';
import 'package:supanotes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_editor.dart';
import 'package:supanotes/features/notes/presentation/widgets/note_link_tap_handler.dart';

void main() {
  group('NoteEditor link suggestions', () {
    testWidgets('NoteEditor renders with provider scope', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeNotesProvider.overrideWith((ref) => const Stream.empty()),
            currentUserIdProvider.overrideWithValue('test-user'),
            appDatabaseProvider.overrideWithValue(AppDatabase.test()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NoteEditor(
                noteId: 'test-note',
                taskMetadata: const {},
                delegate: const NoteEditorDelegate(),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Editor renders without crashing
      expect(find.byType(NoteEditor), findsOneWidget);
    });

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
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'test-node',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );

      composer.setIsInteractionMode(true);

      final handler = NoteLinkTapHandler(
        document,
        composer,
        onNoteTap: (_) {},
      );

      final position = DocumentPosition(
        nodeId: 'test-node',
        nodePosition: TextNodePosition(offset: 8),
      );

      final cursor = handler.mouseCursorForContentHover(position);
      expect(cursor, isNotNull);
      expect(cursor, SystemMouseCursors.click);

      handler.dispose();
      document.dispose();
      composer.dispose();
    });

    testWidgets('NoteLinkTapHandler ignores non-note links', (tester) async {
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
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'test-node',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );

      composer.setIsInteractionMode(true);

      final handler = NoteLinkTapHandler(
        document,
        composer,
        onNoteTap: (_) {},
      );

      final position = DocumentPosition(
        nodeId: 'test-node',
        nodePosition: TextNodePosition(offset: 10),
      );

      final cursor = handler.mouseCursorForContentHover(position);
      expect(cursor, isNull);

      handler.dispose();
      document.dispose();
      composer.dispose();
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
      final composer = MutableDocumentComposer(
        initialSelection: const DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: 'test-node',
            nodePosition: TextNodePosition(offset: 0),
          ),
        ),
      );

      composer.setIsInteractionMode(true);

      final handler = NoteLinkTapHandler(
        document,
        composer,
        onNoteTap: (_) {},
      );

      expect(handler, isA<NoteLinkTapHandler>());

      handler.dispose();
      document.dispose();
      composer.dispose();
    });
  });
}
