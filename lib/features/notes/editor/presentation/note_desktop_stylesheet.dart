import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/features/notes/editor/presentation/note_stylesheet.dart';

/// Writer-like typography metrics for the desktop document surface.
class DesktopNoteStyleConfig {
  DesktopNoteStyleConfig._();

  static const double bodySize = 16.0;
  static const double bodyLineHeight = 1.8;
  static const double h1Size = 25.6;
  static const double h2Size = 22.4;
  static const double h3Size = 19.2;
  static const double quoteSize = 16.0;
  static const double quoteLineHeight = 1.8;
  static const double letterSpacing = -0.48;
  static const double headingTopPadding = 16.0;
  static const double paragraphTopPadding = 0.0;
}

/// Stylesheet entry point for the desktop editor viewport.
Stylesheet desktopNoteStylesheet(
  BuildContext context, {
  EdgeInsets documentPadding = const EdgeInsets.symmetric(horizontal: 24),
}) {
  return buildNoteStylesheet(
    context,
    documentPadding: documentPadding,
    bodySize: DesktopNoteStyleConfig.bodySize,
    h1Size: DesktopNoteStyleConfig.h1Size,
    h2Size: DesktopNoteStyleConfig.h2Size,
    h3Size: DesktopNoteStyleConfig.h3Size,
    quoteSize: DesktopNoteStyleConfig.quoteSize,
    bodyLineHeight: DesktopNoteStyleConfig.bodyLineHeight,
    quoteLineHeight: DesktopNoteStyleConfig.quoteLineHeight,
    letterSpacing: DesktopNoteStyleConfig.letterSpacing,
    h1TopPadding: DesktopNoteStyleConfig.headingTopPadding,
    h2TopPadding: DesktopNoteStyleConfig.headingTopPadding,
    h3TopPadding: DesktopNoteStyleConfig.headingTopPadding,
    paragraphTopPadding: DesktopNoteStyleConfig.paragraphTopPadding,
  );
}
