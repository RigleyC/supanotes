library;

import 'package:flutter/material.dart';

import 'package:supanotes/features/search/domain/search_result_model.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.query,
    required this.onTap,
  });

  final SearchResultModel result;
  final String query;
  final VoidCallback onTap;

  static const _fallbackTitle = 'Sem título';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();

    final title = result.title.trim().isNotEmpty
        ? result.title.trim()
        : _fallbackTitle;
    final excerpt = result.excerpt.trim();

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (excerpt.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                _HighlightedText(
                  text: excerpt,
                  query: query,
                  baseStyle: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  highlightStyle: textTheme.bodyMedium?.copyWith(
                    color: semantic?.highlightForeground,
                    backgroundColor: semantic?.highlightBackground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Two-line excerpt with case-insensitive highlight of every [query]
/// occurrence.
///
/// Implemented as a [RichText] of `TextSpan`s rather than as a
/// `Stack`-of-overlays so the highlight wraps with the text and the
/// ellipsis at the end of line 2 still works. When [query] is empty the
/// excerpt is rendered as a single plain span.
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.baseStyle,
    required this.highlightStyle,
  });

  final String text;
  final String query;
  final TextStyle? baseStyle;
  final TextStyle? highlightStyle;

  @override
  Widget build(BuildContext context) {
    final spans = _buildSpans();
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  List<TextSpan> _buildSpans() {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return [TextSpan(text: text)];
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = trimmedQuery.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;

    while (cursor < text.length) {
      final hit = lowerText.indexOf(lowerQuery, cursor);
      if (hit < 0) {
        spans.add(TextSpan(text: text.substring(cursor)));
        break;
      }
      if (hit > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, hit)));
      }
      final end = hit + lowerQuery.length;
      spans.add(
        TextSpan(text: text.substring(hit, end), style: highlightStyle),
      );
      cursor = end;
    }

    return spans;
  }
}
