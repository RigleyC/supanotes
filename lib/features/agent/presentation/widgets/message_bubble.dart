import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

import '../../domain/message_model.dart';

/// Renders a single chat message as a coloured bubble.
///
///   * User messages    — right-aligned, primary background.
///   * Assistant / etc. — left-aligned, surface-container background.
///
/// Markdown support is intentionally minimal: triple-backtick blocks
/// render as a monospace, bordered code panel; inline `**bold**` is
/// parsed into weighted spans. Everything else is treated as plain
/// selectable text. The implementation is local (no `flutter_markdown`
/// dependency) per the FE-7 spec.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final MessageModel message;

  bool get _isUser => message.role == MessageRole.user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = AppTypography.textTheme;

    final bg = _isUser ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = _isUser ? scheme.onPrimary : scheme.onSurface;
    final crossAxis = _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final maxWidth = MediaQuery.of(context).size.width * 0.78;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        mainAxisAlignment:
            _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Flexible(
            child: Column(
              crossAxisAlignment: crossAxis,
              children: <Widget>[
                Container(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(AppSpacing.radiusLg),
                      topRight: const Radius.circular(AppSpacing.radiusLg),
                      bottomLeft: Radius.circular(
                        _isUser ? AppSpacing.radiusLg : AppSpacing.radiusSm,
                      ),
                      bottomRight: Radius.circular(
                        _isUser ? AppSpacing.radiusSm : AppSpacing.radiusLg,
                      ),
                    ),
                  ),
                  child: _MarkdownText(text: message.content, color: fg),
                ),
                const SizedBox(height: AppSpacing.xs / 2),
                Text(
                  _formatTime(message.createdAt),
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.textTheme.bodyMedium?.copyWith(color: color);
    final code = AppTypography.textTheme.bodyMedium?.copyWith(
      color: color,
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Courier', 'monospace'],
    );

    final segments = _splitCodeBlocks(text);
    if (segments.length == 1 && !segments.first.isCodeBlock) {
      return SelectableText.rich(
        _parseInlineBold(segments.first.text, base!),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final seg in segments)
          if (seg.isCodeBlock)
            _CodeBlock(text: seg.text, baseStyle: code!)
          else
            SelectableText.rich(_parseInlineBold(seg.text, base!)),
      ],
    );
  }

  static List<_Segment> _splitCodeBlocks(String text) {
    final result = <_Segment>[];
    final pattern = RegExp(r'```([\s\S]*?)```');
    int last = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > last) {
        result.add(_Segment(text.substring(last, match.start), false));
      }
      result.add(_Segment(match.group(1)!.trim(), true));
      last = match.end;
    }
    if (last < text.length) {
      result.add(_Segment(text.substring(last), false));
    }
    return result;
  }

  static TextSpan _parseInlineBold(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: base.copyWith(fontWeight: FontWeight.w600),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    if (spans.isEmpty) {
      return TextSpan(text: text, style: base);
    }
    return TextSpan(children: spans);
  }
}

class _Segment {
  const _Segment(this.text, this.isCodeBlock);
  final String text;
  final bool isCodeBlock;
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text, required this.baseStyle});

  final String text;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SelectableText(text, style: baseStyle),
    );
  }
}
