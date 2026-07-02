import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

class RichCommonEditorOperations extends CommonEditorOperations {
  RichCommonEditorOperations({
    required super.editor,
    required super.document,
    required super.composer,
    required super.documentLayoutResolver,
  });

  @override
  void copy() {
    final selection = composer.selection;
    if (selection != null && !selection.isCollapsed) {
      document.copyAsRichTextWithPlainTextFallback(selection: selection);
    }
  }

  @override
  void cut() {
    final selection = composer.selection;
    if (selection != null && !selection.isCollapsed) {
      document.copyAsRichTextWithPlainTextFallback(selection: selection);
      deleteSelection(TextAffinity.downstream);
    }
  }

  @override
  void paste() {
    pasteIntoEditorFromNativeClipboard(editor);
  }
}
