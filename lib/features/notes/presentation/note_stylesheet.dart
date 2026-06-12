import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

/// Returns a [Stylesheet] adapted to the current [BuildContext] theme.
///
/// Must be called inside a [build] method — it reads [Theme.of(context)]
/// so the editor text colours respond to light / dark mode correctly.
Stylesheet noteStylesheet(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final onSurface = colorScheme.onSurface;
  final onSurfaceVariant = colorScheme.onSurfaceVariant;

  return Stylesheet(
    documentPadding: EdgeInsets.zero,
    inlineTextStyler: defaultInlineTextStyler,
    inlineWidgetBuilders: defaultInlineWidgetBuilderChain,
    rules: [
      StyleRule(
        BlockSelector.all,
        (doc, docNode) => {
          Styles.maxWidth: 640.0,
          Styles.padding: const CascadingPadding.symmetric(horizontal: 24),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 16,
            height: 1.4,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('header1'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 28),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('header2'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 24),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('header3'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 20),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        },
      ),
      StyleRule(
        const BlockSelector('paragraph'),
        (doc, docNode) => {Styles.padding: const CascadingPadding.only(top: 12)},
      ),
      StyleRule(
        const BlockSelector('paragraph').after('header1'),
        (doc, docNode) => {Styles.padding: const CascadingPadding.only(top: 16)},
      ),
      StyleRule(
        const BlockSelector('paragraph').after('header2'),
        (doc, docNode) => {Styles.padding: const CascadingPadding.only(top: 16)},
      ),
      StyleRule(
        const BlockSelector('paragraph').after('header3'),
        (doc, docNode) => {Styles.padding: const CascadingPadding.only(top: 16)},
      ),
      StyleRule(
        const BlockSelector('listItem'),
        (doc, docNode) => {Styles.padding: const CascadingPadding.only(top: 12)},
      ),
      StyleRule(
        const BlockSelector('task'),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(top: 0),
          Styles.textStyle: TextStyle(
            color: onSurface,
            fontSize: 16,
            height: 1.4,
          ),
        },
      ),
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
      StyleRule(
        BlockSelector.all.last(),
        (doc, docNode) => {
          Styles.padding: const CascadingPadding.only(bottom: 96),
        },
      ),
    ],
  );
}
