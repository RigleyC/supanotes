import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// Returns a [Stylesheet] that inherits from [defaultStylesheet] and only
/// overrides what's needed: theme-adaptive colours, tighter list spacing,
/// and the `task` block type.
Stylesheet noteStylesheet(
  BuildContext context, {
  EdgeInsets documentPadding = const EdgeInsets.symmetric(horizontal: 24),
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  return defaultStylesheet.copyWith(
    documentPadding: documentPadding,
    inlineTextStyler: (attributions, existingStyle) {
      for (final attribution in attributions) {
        if (attribution is LinkAttribution &&
            attribution.launchableUri.scheme == 'note') {
          return existingStyle.copyWith(
            color: Colors.white,
            background: Paint()
              ..color = const Color(0xFF7C3AED)
              ..style = PaintingStyle.fill,
          );
        }
      }
      return defaultStylesheet.inlineTextStyler(attributions, existingStyle);
    },
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
      // First header1 has no top padding — documentPadding accounts for it.
      StyleRule(
        const BlockSelector('header1').first(),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(bottom: 12),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 38,
            fontWeight: FontWeight.bold,
          ),
        },
      ),
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
      // Task block — padding is managed inside CustomTaskComponent so the
      // TaskExitAnimator can collapse it fully when hiding completed tasks.
      StyleRule(
        const BlockSelector('task'),
        (doc, docNode) {
          return {
            Styles.textStyle: TextStyle(
              color: onSurface,
              fontSize: 18,
              height: 1.4,
            ),
          };
        },
      ),
      // Paragraph spacing.
      StyleRule(
        const BlockSelector('paragraph'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 24),
        },
      ),
    ],
  );
}
