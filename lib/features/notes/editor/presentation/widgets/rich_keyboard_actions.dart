import 'package:flutter/services.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/clipboard_preprocessor.dart';
import 'package:supanotes/features/notes/editor/presentation/widgets/rich_clipboard_serializers.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

ExecutionInstruction insertEmptyTaskBeforeMetadataTaskOnEnter({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent ||
      (keyEvent.logicalKey != LogicalKeyboardKey.enter &&
          keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) ||
      HardwareKeyboard.instance.isShiftPressed ||
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isAltPressed ||
      HardwareKeyboard.instance.isMetaPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null || !selection.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }
  final position = selection.extent.nodePosition;
  final node = editContext.document.getNodeById(selection.extent.nodeId);
  if (position is! TextNodePosition ||
      position.offset != 0 ||
      node is! TaskNode ||
      node.text.isEmpty) {
    return ExecutionInstruction.continueExecution;
  }

  final emptyTask = TaskNode(
    id: Editor.createNodeId(),
    text: AttributedText(),
    isComplete: false,
    indent: node.indent,
  );
  editContext.editor.execute([
    InsertNodeAtIndexRequest(
      nodeIndex: editContext.document.getNodeIndexById(node.id),
      newNode: emptyTask,
    ),
    ChangeSelectionRequest(
      DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: emptyTask.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
      ),
      SelectionChangeType.insertContent,
      SelectionReason.userInteraction,
    ),
  ]);
  return ExecutionInstruction.haltExecution;
}

ExecutionInstruction copyAsRichTextWithMarkdownFallbackWhenShortcutIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }
  if (!keyEvent.isPrimaryShortcutKeyPressed ||
      keyEvent.logicalKey != LogicalKeyboardKey.keyC) {
    return ExecutionInstruction.continueExecution;
  }

  final selection = editContext.composer.selection;
  if (selection == null) return ExecutionInstruction.continueExecution;
  if (selection.isCollapsed) return ExecutionInstruction.haltExecution;

  configureRichClipboardSerializers();
  editContext.document.copyAsRichTextWithMarkdownFallback(selection: selection);
  return ExecutionInstruction.haltExecution;
}

/// A [SuperEditor] keyboard action that cuts the document selection as rich text
/// with plain text fallback when CMD + X (Mac) or CTRL + X (Windows/Linux) is pressed.
ExecutionInstruction cutAsRichTextWhenCmdXOrCtrlXIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed ||
      keyEvent.logicalKey != LogicalKeyboardKey.keyX) {
    return ExecutionInstruction.continueExecution;
  }
  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (selection.isCollapsed) {
    return ExecutionInstruction.haltExecution;
  }

  configureRichClipboardSerializers();
  editContext.document.copyAsRichTextWithPlainTextFallback(
    selection: selection,
  );
  editContext.commonOps.deleteSelection(TextAffinity.downstream);

  return ExecutionInstruction.haltExecution;
}

/// A [SuperEditor] keyboard action that intercepts Cmd+V / Ctrl+V,
/// preprocesses the clipboard to replace unicode bullet characters with
/// standard markdown markers, and then performs the rich-text paste.
ExecutionInstruction pastePreprocessedRichText({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed ||
      keyEvent.logicalKey != LogicalKeyboardKey.keyV) {
    return ExecutionInstruction.continueExecution;
  }
  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  pasteWithPreprocessingAndReport(editContext.editor);

  return ExecutionInstruction.haltExecution;
}

/// Prepends rich copy, cut, and paste actions to the list of [baseActions].
List<SuperEditorKeyboardAction> buildRichKeyboardActions({
  required List<SuperEditorKeyboardAction> baseActions,
}) {
  configureRichClipboardSerializers();
  return [
    copyAsRichTextWithMarkdownFallbackWhenShortcutIsPressed,
    cutAsRichTextWhenCmdXOrCtrlXIsPressed,
    pastePreprocessedRichText,
    insertEmptyTaskBeforeMetadataTaskOnEnter,
    ...baseActions,
  ];
}
