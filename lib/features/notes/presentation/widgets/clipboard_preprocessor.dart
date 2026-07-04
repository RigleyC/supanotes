import 'dart:async';
import 'dart:convert';

import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

const _unicodeBullets = <String>{
  '\u{2022}', // bullet
  '\u{25E6}', // white bullet
  '\u{25AA}', // black small square
  '\u{25AB}', // white small square
};

String preprocessClipboardText(String text) {
  var result = text;
  for (final bullet in _unicodeBullets) {
    result = result.replaceAll('$bullet ', '- ');
    result = result.replaceAll(bullet, '- ');
  }
  return result;
}

Future<void> pasteWithPreprocessing(Editor editor) async {
  await pasteIntoEditorFromNativeClipboard(
    editor,
    customInserter: (editor, reader) async {
      // 1. Try html
      if (reader.canProvide(Formats.htmlText)) {
        final html = await reader.readValue(Formats.htmlText);
        if (html != null) {
          final preprocessedHtml = preprocessClipboardText(html);
          editor.pasteHtml(editor, preprocessedHtml);
          return true;
        }
      }

      // 2. Try markdown
      if (reader.canProvide(Formats.md)) {
        final completer = Completer<bool>();
        final progress = reader.getFile(
          Formats.md,
          (file) async {
            final data = await file.readAll();
            final markdown = utf8.decode(data);
            if (markdown.isNotEmpty) {
              final preprocessedMarkdown = preprocessClipboardText(markdown);
              editor.pasteMarkdown(editor, preprocessedMarkdown);
              completer.complete(true);
            } else {
              completer.complete(false);
            }
          },
          onError: (_) {
            completer.complete(false);
          },
        );
        if (progress != null) {
          final success = await completer.future;
          if (success) return true;
        }
      }

      // 3. Try plain text
      if (reader.canProvide(Formats.plainText)) {
        final text = await reader.readValue(Formats.plainText);
        if (text != null) {
          final preprocessedText = preprocessClipboardText(text);
          final selection = editor.composer.selection;
          if (selection != null) {
            DocumentPosition? pastePosition = selection.extent;

            if (!selection.isCollapsed) {
              pastePosition = CommonEditorOperations.getDocumentPositionAfterExpandedDeletion(
                document: editor.document,
                selection: editor.composer.selection!,
              );

              if (pastePosition == null) {
                return false;
              }

              // Delete the selected content.
              editor.execute([
                DeleteContentRequest(documentRange: editor.composer.selection!),
                ChangeSelectionRequest(
                  DocumentSelection.collapsed(position: pastePosition),
                  SelectionChangeType.deleteContent,
                  SelectionReason.userInteraction,
                ),
              ]);
            }

            // Paste clipboard text.
            editor.execute([
              PasteEditorRequest(
                content: preprocessedText,
                pastePosition: pastePosition,
              ),
            ]);
            return true;
          }
        }
      }

      return false;
    },
  );
}
