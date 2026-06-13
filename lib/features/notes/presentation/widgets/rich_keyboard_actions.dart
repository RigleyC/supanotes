import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

ExecutionInstruction cutAsRichTextWhenCmdXOrCtrlXIsPressed({
  required SuperEditorContext editContext,
  required KeyEvent keyEvent,
}) {
  if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isPrimaryShortcutKeyPressed || keyEvent.logicalKey != LogicalKeyboardKey.keyX) {
    return ExecutionInstruction.continueExecution;
  }
  final selection = editContext.composer.selection;
  if (selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (selection.isCollapsed) {
    return ExecutionInstruction.haltExecution;
  }

  editContext.document.copyAsRichTextWithPlainTextFallback(
    selection: selection,
  );
  editContext.commonOps.deleteSelection(TextAffinity.downstream);

  return ExecutionInstruction.haltExecution;
}

List<SuperEditorKeyboardAction> buildRichKeyboardActions({
  required List<SuperEditorKeyboardAction> baseActions,
}) {
  return [
    copyAsRichTextWhenCmdCOrCtrlCIsPressed,
    cutAsRichTextWhenCmdXOrCtrlXIsPressed,
    pasteRichTextOnCmdCtrlV,
    ...baseActions,
  ];
}
