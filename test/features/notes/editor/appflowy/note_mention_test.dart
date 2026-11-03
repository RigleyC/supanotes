import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/catalog/model/note_model.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/note_suggestion_overlay.dart';

void main() {
  test(
    'an @query before the caret becomes a link to the picked note',
    () async {
      const codec = NoteAppFlowyCodec();
      final editorState = EditorState(
        document: codec.toDocument([
          NoteBlock(
            id: 'p',
            type: 'paragraph',
            delta: const [
              {'insert': 'ver @merc'},
            ],
          ),
        ]),
      )..selection = Selection.collapsed(Position(path: [0], offset: 9));

      final mention = noteMentionAt(editorState)!;
      expect(mention.query, 'merc');
      expect(mention.start, 4);

      await applyNoteMention(
        editorState,
        mention,
        NoteModel(
          id: 'n2',
          userId: 'u',
          content: '',
          title: 'Mercado',
          favorite: false,
          archived: false,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          hasRemoteCopy: true,
          isEmptyDraft: false,
        ),
      );

      expect(codec.toBlocks(editorState.document).single.delta, [
        {'insert': 'ver '},
        {
          'insert': 'Mercado',
          'attributes': {'link': 'note://n2'},
        },
      ]);
      expect(editorState.selection!.end.offset, 11);
      expect(noteMentionAt(editorState), isNull);
    },
  );
}
