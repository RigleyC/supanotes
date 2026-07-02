import 'dart:async';

import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

import 'clipboard_preprocessor.dart';

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

  unawaited(pasteWithPreprocessing(editContext.editor));

  return ExecutionInstruction.haltExecution;
}

/// Prepends rich copy, cut, and paste actions to the list of [baseActions].
List<SuperEditorKeyboardAction> buildRichKeyboardActions({
  required List<SuperEditorKeyboardAction> baseActions,
}) {
  return [
    copyAsRichTextWhenCmdCOrCtrlCIsPressed,
    cutAsRichTextWhenCmdXOrCtrlXIsPressed,
    pastePreprocessedRichText,
    ...baseActions,
  ];
}
