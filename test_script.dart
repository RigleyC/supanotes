import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

Widget buildEditor(Document doc, DocumentComposer composer, DocumentEditor editor) {
  return SuperEditor(
    editor: editor,
    stylesheet: Stylesheet(
      inlineTextStyler: defaultInlineTextStyler,
      rules: [],
      selectionStyles: SelectionStyles(
        caretColor: Colors.red,
        selectionColor: Colors.blue,
      ),
    ),
  );
}
