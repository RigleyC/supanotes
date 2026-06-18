import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// Returns a [Stylesheet] that inherits from [defaultStylesheet] and only
/// overrides what's needed: theme-adaptive colours, tighter list spacing,
/// and the `task` block type.
Stylesheet noteStylesheet(BuildContext context, {bool hideCompleted = false}) {
  final colorScheme = Theme.of(context).colorScheme;
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  return defaultStylesheet.copyWith(
    documentPadding: EdgeInsets.symmetric(horizontal: 24),
    rules: [
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
      // Override headers: theme colour + top/bottom spacing.
      StyleRule(
        const BlockSelector('header1'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 24, bottom: 12),
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
          Styles.padding: const CascadingPadding.only(top: 20, bottom: 12),
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
          Styles.padding: const CascadingPadding.only(top: 16, bottom: 8),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        },
      ),
      // List spacing.
      StyleRule(
        const BlockSelector('listItem'),
        (doc, docNode) => {Styles.padding: const CascadingPadding.only(top: 8)},
      ),
      StyleRule(
        const BlockSelector('listItem').last(),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(bottom: 12),
        },
      ),
      // Override blockquote: swap hardcoded grey for theme colour.
      StyleRule(
        const BlockSelector('blockquote'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 8, bottom: 8),
          Styles.textStyle: TextStyle(
            color: onSurfaceVariant,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
        },
      ),
      // Divider spacing.
      StyleRule(
        const BlockSelector('horizontalRule'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 12, bottom: 12),
        },
      ),
      // Task block (not in default stylesheet).
      StyleRule(
        const BlockSelector('task'),
        (doc, docNode) => {
          Styles.padding:
              hideCompleted && docNode is TaskNode && docNode.isComplete
              ? const CascadingPadding.all(0)
              : const CascadingPadding.only(top: 8),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 18,
            height: 1.4,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('task').last(),
        (doc, docNode) => {
          Styles.padding:
              hideCompleted && docNode is TaskNode && docNode.isComplete
              ? const CascadingPadding.all(0)
              : const CascadingPadding.only(bottom: 12),
        },
      ),
    ],
  );
}
