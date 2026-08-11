import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// Builds the shared note stylesheet rules for one layout profile.
///
/// The mobile entry point provides the profile metrics. Keeping the block
/// rules in one place prevents duplicate stylesheets from drifting apart.
Stylesheet buildNoteStylesheet(
  BuildContext context, {
  required EdgeInsets documentPadding,
  required double bodySize,
  required double h1Size,
  required double h2Size,
  required double h3Size,
  required double quoteSize,
  required double bodyLineHeight,
  required double quoteLineHeight,
  required double letterSpacing,
  required double h1TopPadding,
  required double h2TopPadding,
  required double h3TopPadding,
  required double paragraphTopPadding,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final linkColor = colorScheme.primary;
  const editorTextColor = Colors.white;

  return defaultStylesheet.copyWith(
    documentPadding: documentPadding,
    inlineTextStyler: (attributions, existingStyle) {
      for (final attribution in attributions) {
        if (attribution is LinkAttribution &&
            attribution.launchableUri.scheme == 'note') {
          return existingStyle.copyWith(
            color: colorScheme.onPrimary,
            background: Paint()
              ..color = linkColor
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
            color: editorTextColor,
            fontSize: bodySize,
            height: bodyLineHeight,
            letterSpacing: letterSpacing,
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
            color: editorTextColor,
            fontSize: h1Size,
            fontWeight: FontWeight.bold,
            letterSpacing: letterSpacing,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('header1'),
        (doc, docNode) => {
          Styles.padding: CascadingPadding.only(top: h1TopPadding, bottom: 12),
          Styles.textStyle: TextStyle(
            color: editorTextColor,
            fontSize: h1Size,
            fontWeight: FontWeight.bold,
            letterSpacing: letterSpacing,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('header2'),
        (doc, docNode) => {
          Styles.padding: CascadingPadding.only(top: h2TopPadding, bottom: 12),
          Styles.textStyle: TextStyle(
            color: editorTextColor,
            fontSize: h2Size,
            fontWeight: FontWeight.bold,
            letterSpacing: letterSpacing,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('header3'),
        (doc, docNode) => {
          Styles.padding: CascadingPadding.only(top: h3TopPadding, bottom: 8),
          Styles.textStyle: TextStyle(
            color: editorTextColor,
            fontSize: h3Size,
            fontWeight: FontWeight.bold,
            letterSpacing: letterSpacing,
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
            color: editorTextColor,
            fontSize: quoteSize,
            fontWeight: FontWeight.bold,
            height: quoteLineHeight,
            letterSpacing: letterSpacing,
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
      StyleRule(const BlockSelector('task'), (doc, docNode) {
        return {
          Styles.textStyle: TextStyle(
            color: editorTextColor,
            fontSize: bodySize,
            height: bodyLineHeight,
            letterSpacing: letterSpacing,
          ),
        };
      }),
      // Paragraph spacing.
      StyleRule(
        const BlockSelector('paragraph'),
        (doc, docNode) => {
          Styles.padding: CascadingPadding.only(top: paragraphTopPadding),
        },
      ),
      StyleRule(
        const BlockSelector('corrupted'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 24),
          Styles.textStyle: TextStyle(
            color: colorScheme.onErrorContainer,
            background: Paint()
              ..color = colorScheme.errorContainer
              ..style = PaintingStyle.fill,
            fontSize: bodySize,
            fontWeight: FontWeight.bold,
            height: bodyLineHeight,
            letterSpacing: letterSpacing,
          ),
        },
      ),
    ],
  );
}
