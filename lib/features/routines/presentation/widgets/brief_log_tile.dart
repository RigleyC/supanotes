import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../shared/theme/app_spacing.dart';
import '../../domain/routine_log_model.dart';

const _emptyBody = '(vazio)';
const _statusUnknownFallback = 'Desconhecido';

/// One row of the brief history list. Shows a date stamp, a 2-line
/// preview of the content, a status chip, and — when the run
/// completed successfully and a Telegram side-effect happened (no
/// flag in the schema yet) — leaves a small visual cue.
///
/// Tap toggles the inline expansion that reveals the full body.
/// The widget is a plain [StatefulWidget] because the expansion flag
/// is purely local UI state and does not deserve a Riverpod entry.
class BriefLogTile extends StatefulWidget {
  const BriefLogTile({super.key, required this.log});

  final RoutineLogModel log;

  @override
  State<BriefLogTile> createState() => _BriefLogTileState();
}

class _BriefLogTileState extends State<BriefLogTile> {
  static const _dateFormat = "dd 'de' MMM, yyyy";
  static const _timeFormat = 'HH:mm';
  static const _statusSuccess = 'Sucesso';
  static const _statusFailed = 'Falhou';
  static const _statusUnknownPrefix = 'Status:';

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final log = widget.log;

    final localTime = log.createdAt.toLocal();
    final dateLabel = DateFormat(_dateFormat, 'pt_BR').format(localTime);
    final timeLabel = DateFormat(_timeFormat).format(localTime);

    final statusLabel = _statusLabel(log.status);
    final isSuccess = log.isSuccess;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                  color: isSuccess ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    dateLabel,
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  timeLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _PreviewText(text: _bodyFor(log), expanded: _expanded),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                _StatusChip(label: statusLabel, success: isSuccess),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _bodyFor(RoutineLogModel log) {
    if (log.isSuccess) return log.content;
    if (log.errorMsg != null && log.errorMsg!.isNotEmpty) return log.errorMsg!;
    return log.content;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'success':
        return _statusSuccess;
      case 'failed':
        return _statusFailed;
      default:
        return '$_statusUnknownPrefix $status';
    }
  }
}

class _PreviewText extends StatelessWidget {
  const _PreviewText({required this.text, required this.expanded});

  final String text;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (expanded) {
      return SelectableText(
        text,
        style: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
          height: 1.4,
        ),
      );
    }

    final preview = _firstTwoLines(text);
    return Text(
      preview.isEmpty ? _emptyBody : preview,
      style: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _firstTwoLines(String input) {
    if (input.isEmpty) return '';
    final lines = const LineSplitter().convert(input);
    return lines.take(2).join('\n').trim();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.success});

  final String label;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final bg = success ? scheme.primaryContainer : scheme.errorContainer;
    final fg = success ? scheme.onPrimaryContainer : scheme.onErrorContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        label.isEmpty ? _statusUnknownFallback : label,
        style: textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
