import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
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

Future<void> pasteWithPreprocessing(
  Editor editor, {
  SystemClipboard? testClipboard,
}) async {
  final destination = editor.composer.selection;
  if (destination == null) return;

  await pasteIntoEditorFromNativeClipboard(
    editor,
    testClipboard: testClipboard,
    customInserter: (editor, reader) =>
        _pasteSingleLineTaskText(editor, reader, destination),
    customFileInserters: {
      Formats.md: (editor, reader) =>
          _pastePreprocessedMarkdownFile(editor, reader, destination),
      for (final format in _bitmapFormats)
        format: (editor, reader) =>
            _pastePreprocessedImage(editor, reader, destination, format),
    },
    customValueInserters: {
      Formats.htmlText: (editor, reader) =>
          _pastePreprocessedHtml(editor, reader, destination),
      Formats.uri: (editor, reader) =>
          _pastePreprocessedUri(editor, reader, destination),
      Formats.plainText: (editor, reader) =>
          _pastePreprocessedPlainText(editor, reader, destination),
    },
  );
}

const _bitmapFormats = <SimpleFileFormat>[
  Formats.png,
  Formats.jpeg,
  Formats.heic,
  Formats.gif,
  Formats.bmp,
  Formats.webp,
];

Future<bool> _pastePreprocessedImage(
  Editor editor,
  ClipboardReader reader,
  DocumentSelection destination,
  FileFormat format,
) async {
  if (!reader.canProvide(format)) return false;

  final completer = Completer<bool>();
  final progress = reader.getFile(
    format,
    (file) async {
      try {
        final imageData = await file.readAll();
        final image = await decodeImageFromList(imageData);
        if (!_restorePasteSelection(editor, destination)) {
          completer.complete(false);
          image.dispose();
          return;
        }
        editor.execute([
          InsertNodeAtCaretRequest(
            node: BitmapImageNode(
              id: Editor.createNodeId(),
              imageData: imageData,
              expectedBitmapSize: ExpectedSize(image.width, image.height),
            ),
          ),
        ]);
        image.dispose();
        completer.complete(true);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }
    },
    onError: (error) {
      if (!completer.isCompleted) completer.completeError(error);
    },
  );
  if (progress == null) return false;
  return completer.future;
}

/// Starts a paste from an unawaited keyboard/common-operations callback while
/// making failures observable through Flutter's standard error boundary.
void pasteWithPreprocessingAndReport(Editor editor) {
  unawaited(
    pasteWithPreprocessing(editor).catchError((Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'supanotes clipboard',
          context: ErrorDescription('while pasting clipboard content'),
        ),
      );
    }),
  );
}

Future<bool> _pasteSingleLineTaskText(
  Editor editor,
  ClipboardReader reader,
  DocumentSelection destination,
) async {
  if (!_selectionIsInsideTask(editor, destination) ||
      !reader.canProvide(Formats.plainText)) {
    return false;
  }

  final text = await reader.readValue(Formats.plainText);
  if (text == null || text.contains(RegExp(r'[\r\n]'))) return false;

  return pastePlainTextAtCurrentSelection(
    editor,
    preprocessClipboardText(text),
    selection: destination,
  );
}

Future<bool> _pastePreprocessedHtml(
  Editor editor,
  ClipboardReader reader,
  DocumentSelection destination,
) async {
  for (final item in reader.items) {
    if (!item.canProvide(Formats.htmlText)) continue;

    final html = await item.readValue(Formats.htmlText);
    if (html == null) continue;

    if (!_restorePasteSelection(editor, destination)) return false;
    if (_containsClipboardCheckbox(html)) {
      editor.pasteMarkdown(editor, clipboardHtmlToMarkdown(html));
    } else {
      editor.pasteHtml(editor, preprocessClipboardHtml(html));
    }
    return true;
  }

  return false;
}

Future<bool> _pastePreprocessedMarkdownFile(
  Editor editor,
  ClipboardReader reader,
  DocumentSelection destination,
) async {
  for (final item in reader.items) {
    if (!item.canProvide(Formats.md)) continue;

    final completer = Completer<bool>();
    final progress = item.getFile(Formats.md, (file) async {
      final data = await file.readAll();
      final markdown = utf8.decode(data);
      if (markdown.isNotEmpty) {
        if (!_restorePasteSelection(editor, destination)) {
          completer.complete(false);
          return;
        }
        editor.pasteMarkdown(editor, preprocessClipboardText(markdown));
        completer.complete(true);
      } else {
        completer.complete(false);
      }
    }, onError: completer.completeError);
    if (progress != null) return completer.future;
  }

  return false;
}

Future<bool> _pastePreprocessedPlainText(
  Editor editor,
  ClipboardReader reader,
  DocumentSelection destination,
) async {
  if (!reader.canProvide(Formats.plainText)) return false;

  final text = await reader.readValue(Formats.plainText);
  if (text == null) return false;

  final preprocessedText = preprocessClipboardText(text);
  if (_isMarkdown(preprocessedText)) {
    if (!_restorePasteSelection(editor, destination)) return false;
    editor.pasteMarkdown(editor, preprocessedText);
    return true;
  }

  return pastePlainTextAtCurrentSelection(
    editor,
    preprocessedText,
    selection: destination,
  );
}

Future<bool> _pastePreprocessedUri(
  Editor editor,
  ClipboardReader reader,
  DocumentSelection destination,
) async {
  for (final item in reader.items) {
    if (!item.canProvide(Formats.uri)) continue;
    final namedUri = await item.readValue<NamedUri>(Formats.uri);
    if (namedUri == null) continue;
    return pastePlainTextAtCurrentSelection(
      editor,
      namedUri.uri.toString(),
      selection: destination,
    );
  }
  return false;
}

bool _containsClipboardCheckbox(String html) {
  return RegExp(
    r'''<input\b[^>]*\btype=["']?checkbox''',
    caseSensitive: false,
  ).hasMatch(html);
}

bool _selectionIsInsideTask(Editor editor, DocumentSelection selection) {
  return editor.document.getNodeById(selection.extent.nodeId) is TaskNode;
}

bool pastePlainTextAtCurrentSelection(
  Editor editor,
  String text, {
  DocumentSelection? selection,
}) {
  final destination = selection ?? editor.composer.selection;
  if (destination == null) return false;
  return pastePlainTextAtSelection(editor, destination, text);
}

bool pastePlainTextAtSelection(
  Editor editor,
  DocumentSelection selection,
  String text,
) {
  if (!_restorePasteSelection(editor, selection)) return false;

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

bool _restorePasteSelection(Editor editor, DocumentSelection selection) {
  if (editor.document.getNodeById(selection.base.nodeId) == null ||
      editor.document.getNodeById(selection.extent.nodeId) == null) {
    return false;
  }
  editor.composer.setSelectionWithReason(
    selection,
    SelectionReason.userInteraction,
  );
  return true;
}
