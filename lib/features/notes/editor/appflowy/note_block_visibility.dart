import 'package:supanotes/features/notes/editor/appflowy/blocks/note_task_block.dart';
import 'package:supanotes/features/notes/editor/appflowy/note_appflowy_codec.dart';
import 'package:supanotes/features/notes/editor/document/note_blocks.dart';

/// Which blocks of a note the editor leaves out, and edits to those blocks.
///
/// Hidden blocks are part of the synced note but not of the editor's
/// document, so the user cannot edit them by accident.
abstract interface class NoteBlockVisibility {
  /// Leaves out the blocks [hides] matches (null shows all).
  Future<void> hideBlocks(bool Function(NoteBlock block)? hides);

  /// Applies [hides] again, e.g. after a task finished its exit animation.
  Future<void> refreshHidden();

  /// The hidden block [blockId], or null when it is shown or unknown.
  NoteBlock? hiddenBlock(String blockId);

  /// Replaces hidden block [blockId] with [block], or deletes it when
  /// [block] is null (task commands on a hidden task).
  Future<void> replaceHiddenBlock(String blockId, NoteBlock? block);
}

/// Whether [block] is a task whose current occurrence is done.
bool isCompletedTaskBlock(NoteBlock block) =>
    block.type == 'task' &&
    resolveTaskCompletion(const NoteAppFlowyCodec().toNode(block)).isComplete;
