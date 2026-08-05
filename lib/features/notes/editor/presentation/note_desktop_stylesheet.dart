import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/presentation/note_stylesheet.dart';

/// Stylesheet entry point for the desktop editor viewport.
Stylesheet desktopNoteStylesheet(
  BuildContext context, {
  EdgeInsets documentPadding = const EdgeInsets.symmetric(horizontal: 24),
}) {
  return buildNoteStylesheet(
    context,
    documentPadding: documentPadding,
    bodySize: 15,
    h1Size: 28,
    h2Size: 22,
    h3Size: 18,
    quoteSize: 16,
    bodyLineHeight: 1.55,
    quoteLineHeight: 1.5,
  );
}
