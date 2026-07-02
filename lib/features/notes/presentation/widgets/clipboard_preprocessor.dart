import 'dart:async';

import 'package:flutter/services.dart';
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

/// Reads the native clipboard, preprocesses bullet characters, writes the
/// cleaned text back, then triggers super_editor's rich-text paste.
///
/// NOTE: This mutates the system clipboard as a side effect. If the user
/// pastes and immediately switches apps, their clipboard will contain the
/// preprocessed text rather than the original. This is a pragmatic tradeoff
/// because super_editor's paste API does not support injecting content
/// directly without going through the native clipboard.
Future<void> pasteWithPreprocessing(Editor editor) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text != null) {
    final preprocessed = preprocessClipboardText(data!.text!);
    await Clipboard.setData(ClipboardData(text: preprocessed));
  }
  pasteIntoEditorFromNativeClipboard(editor);
}
