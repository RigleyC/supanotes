import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// Returns a [Stylesheet] that inherits from [defaultStylesheet] and only
/// overrides what's needed: theme-adaptive colours, tighter list spacing,
/// and the `task` block type.
Stylesheet noteStylesheet(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  return defaultStylesheet.copyWith(rules: [
    // Override base rule: swap hardcoded Colors.black for theme colour.
    StyleRule(
      BlockSelector.all,
      (doc, docNode) => {
        Styles.textStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          height: 1.4,
        ),
      },
    ),
    // Override headers: swap hardcoded #333333 for theme colour.
    StyleRule(
      const BlockSelector('header1'),
      (doc, docNode) => {
        Styles.textStyle: TextStyle(
          color: onSurface,
          fontSize: 38,
          fontWeight: FontWeight.bold,
        ),
      },
    ),
    StyleRule(
      const BlockSelector('header2'),
      (doc, docNode) => {
        Styles.textStyle: TextStyle(
          color: onSurface,
          fontSize: 26,
          fontWeight: FontWeight.bold,
        ),
      },
    ),
    StyleRule(
      const BlockSelector('header3'),
      (doc, docNode) => {
        Styles.textStyle: TextStyle(
          color: onSurface,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      },
    ),
    // Tighter list spacing (default is 24).
    StyleRule(
      const BlockSelector('listItem'),
      (doc, docNode) => {
        Styles.padding: const CascadingPadding.only(top: 2),
      },
    ),
    // Override blockquote: swap hardcoded grey for theme colour.
    StyleRule(
      const BlockSelector('blockquote'),
      (doc, docNode) => {
        Styles.textStyle: TextStyle(
          color: onSurfaceVariant,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          height: 1.4,
        ),
      },
    ),
    // Task block (not in default stylesheet).
    StyleRule(
      const BlockSelector('task'),
      (doc, docNode) => {
        Styles.padding: const CascadingPadding.only(top: 0),
        Styles.textStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          height: 1.4,
        ),
      },
    ),
  ]);
}
