import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/presentation/note_stylesheet.dart';

/// Stylesheet entry point for phone and tablet note editing.
Stylesheet mobileNoteStylesheet(
  BuildContext context, {
  EdgeInsets documentPadding = const EdgeInsets.symmetric(horizontal: 24),
}) {
  return buildNoteStylesheet(
    context,
    documentPadding: documentPadding,
    bodySize: 18,
    h1Size: 38,
    h2Size: 26,
    h3Size: 22,
    quoteSize: 20,
    bodyLineHeight: 1.4,
    quoteLineHeight: 1.4,
  );
}
