import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/domain/note_model.dart';

void applyHashtagSuggestion({
  required Editor editor,
  required String nodeId,
  required int tagStartOffset,
  required int tagEndOffset,
  required NoteModel note,
  required void Function() onPersist,
}) {
  editor.execute([
    DeleteContentRequest(
      documentRange: DocumentRange(
        start: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: tagStartOffset),
        ),
        end: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: tagEndOffset),
        ),
      ),
    ),
    InsertTextRequest(
      documentPosition: DocumentPosition(
        nodeId: nodeId,
        nodePosition: TextNodePosition(offset: tagStartOffset),
      ),
      textToInsert: note.title,
      attributions: {LinkAttribution.fromUri(Uri.parse('note://${note.id}'))},
    ),
  ]);

  editor.execute([
    ChangeSelectionRequest(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: nodeId,
          nodePosition: TextNodePosition(offset: tagStartOffset + note.title.length),
        ),
      ),
      SelectionChangeType.placeCaret,
      SelectionReason.userInteraction,
    ),
  ]);

  onPersist();
}
