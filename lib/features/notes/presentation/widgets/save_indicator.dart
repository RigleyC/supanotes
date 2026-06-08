/// Tiny status pill that mirrors the editor's save state.
///
/// Driven by a [EditorStatus] enum. The "Salvo" state auto-fades back to
/// `idle` two seconds after it is shown so the indicator does not stay
/// pinned to the AppBar forever after a successful write.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:supanotes/features/notes/domain/editor_status.dart';
import 'package:supanotes/shared/theme/app_colors.dart';
import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/theme/app_typography.dart';

class SaveIndicator extends StatefulWidget {
  const SaveIndicator({super.key, required this.state});

  final EditorStatus state;

  @override
  State<SaveIndicator> createState() => _SaveIndicatorState();
}

class _SaveIndicatorState extends State<SaveIndicator> {
  Timer? _fadeTimer;

  @override
  void didUpdateWidget(covariant SaveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFade();
  }

  @override
  void initState() {
    super.initState();
    _scheduleFade();
  }

  void _scheduleFade() {
    _fadeTimer?.cancel();
    if (widget.state == EditorStatus.saved) {
      _fadeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state == EditorStatus.idle) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, label, color) = switch (widget.state) {
      EditorStatus.saving => (
          Icons.sync,
          'Salvando…',
          colorScheme.onSurfaceVariant,
        ),
      EditorStatus.saved => (
          Icons.check_circle_outline,
          'Salvo',
          AppColors.success,
        ),
      EditorStatus.error => (
          Icons.error_outline,
          'Erro ao salvar',
          colorScheme.error,
        ),
      EditorStatus.idle => (Icons.circle, '', colorScheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
