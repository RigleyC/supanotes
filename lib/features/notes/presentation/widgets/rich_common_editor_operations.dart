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
    if (composer.selection != null && !composer.selection!.isCollapsed) {
      document.copyAsRichTextWithPlainTextFallback(
        selection: composer.selection!,
      );
    }
  }

  @override
  void cut() {
    if (composer.selection != null && !composer.selection!.isCollapsed) {
      document.copyAsRichTextWithPlainTextFallback(
        selection: composer.selection!,
      );
      deleteSelection(TextAffinity.downstream);
    }
  }

  @override
  void paste() {
    pasteIntoEditorFromNativeClipboard(editor);
  }
}
