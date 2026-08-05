import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// Builds the shared note stylesheet rules for one layout profile.
///
/// The mobile and desktop entry points provide the profile metrics. Keeping
/// the block rules here prevents the two stylesheets from drifting apart while
/// allowing their typography to evolve independently.
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
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final linkColor = colorScheme.primary;
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

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
            color: onSurface,
            fontSize: bodySize,
            height: bodyLineHeight,
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
            fontSize: h1Size,
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
            fontSize: h1Size,
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
            fontSize: h2Size,
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
            fontSize: h3Size,
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
            fontSize: quoteSize,
            fontWeight: FontWeight.bold,
            height: quoteLineHeight,
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
            color: onSurface,
            fontSize: bodySize,
            height: 1.4,
          ),
        };
      }),
      // Paragraph spacing.
      StyleRule(
        const BlockSelector('paragraph'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 24),
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
          ),
        },
      ),
    ],
  );
}
