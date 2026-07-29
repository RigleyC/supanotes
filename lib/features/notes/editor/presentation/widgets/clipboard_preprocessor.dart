import 'dart:async';
import 'dart:convert';

import 'package:html2md/html2md.dart' as html2md;
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

  // Convert plain "[ ]" or "[x]" at the start of a line to "- [ ]"
  result = result.replaceAll(RegExp(r'^\[\s\] ', multiLine: true), '- [ ] ');
  result = result.replaceAll(RegExp(r'^\[[xX]\] ', multiLine: true), '- [x] ');

  // Rich-text sources often use multiple spaces or a tab after list markers.
  result = result.replaceAllMapped(
    RegExp(r'^(\s*)([-*+]|\d+[.)])[\t ]+', multiLine: true),
    (match) => '${match.group(1)}${match.group(2)} ',
  );

  return result;
}

String preprocessClipboardHtml(String html) {
  final withTaskMarkers = html.replaceAllMapped(
    RegExp(
      r'''<input\b[^>]*\btype=["']?checkbox["']?[^>]*>''',
      caseSensitive: false,
    ),
    (match) =>
        RegExp(
          r'''\bchecked(?:\s*=\s*(?:["']checked["']|["']true["']|checked|true))?''',
          caseSensitive: false,
        ).hasMatch(match.group(0)!)
        ? '[x]'
        : '[ ]',
  );
  return preprocessClipboardText(withTaskMarkers);
}

String clipboardHtmlToMarkdown(String html) {
  final markdown = html2md
      .convert(preprocessClipboardHtml(html))
      .replaceAll(r'\[ \]', '[ ]')
      .replaceAll(r'\[x\]', '[x]')
      .replaceAll(r'\[X\]', '[x]');
  return preprocessClipboardText(markdown);
}

bool _isMarkdown(String text) {
  return RegExp(
    r'^\s*(?:[-*+]|\d+[.)])\s+|^#+ |^> |^```',
    multiLine: true,
  ).hasMatch(text);
}

Future<void> pasteWithPreprocessing(Editor editor) async {
  await pasteIntoEditorFromNativeClipboard(
    editor,
    customInserter: (editor, reader) async {
      if (_selectionIsInsideTask(editor) &&
          reader.canProvide(Formats.plainText)) {
        final text = await reader.readValue(Formats.plainText);
        if (text != null && !text.contains(RegExp(r'[\r\n]'))) {
          return pastePlainTextAtCurrentSelection(
            editor,
            preprocessClipboardText(text),
          );
        }
      }

      // 1. Try html
      if (reader.canProvide(Formats.htmlText)) {
        final html = await reader.readValue(Formats.htmlText);
        if (html != null) {
          if (RegExp(
            r'''<input\b[^>]*\btype=["']?checkbox''',
            caseSensitive: false,
          ).hasMatch(html)) {
            editor.pasteMarkdown(editor, clipboardHtmlToMarkdown(html));
          } else {
            editor.pasteHtml(editor, preprocessClipboardHtml(html));
          }
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
          final isLikelyMarkdown = _isMarkdown(preprocessedText);

          if (isLikelyMarkdown) {
            editor.pasteMarkdown(editor, preprocessedText);
            return true;
          }

          final selection = editor.composer.selection;
          if (selection != null) {
            return pastePlainTextAtCurrentSelection(editor, preprocessedText);
          }
        }
      }

      return false;
    },
  );
}

bool _selectionIsInsideTask(Editor editor) {
  final selection = editor.composer.selection;
  if (selection == null) return false;
  return editor.document.getNodeById(selection.extent.nodeId) is TaskNode;
}

bool pastePlainTextAtCurrentSelection(Editor editor, String text) {
  final selection = editor.composer.selection;
  if (selection == null) return false;

  DocumentPosition? pastePosition = selection.extent;
  if (!selection.isCollapsed) {
    pastePosition =
        CommonEditorOperations.getDocumentPositionAfterExpandedDeletion(
          document: editor.document,
          selection: selection,
        );
    if (pastePosition == null) return false;

    editor.execute([
      DeleteContentRequest(documentRange: selection),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(position: pastePosition),
        SelectionChangeType.deleteContent,
        SelectionReason.userInteraction,
      ),
    ]);
  }

  editor.execute([
    PasteEditorRequest(content: text, pastePosition: pastePosition),
  ]);
  return true;
}
