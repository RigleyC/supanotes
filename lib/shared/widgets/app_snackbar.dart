import 'package:flutter/material.dart';

enum _SnackType { success, error, info, task }

class AppMessenger {
  AppMessenger._();

  static final GlobalKey<ScaffoldMessengerState> key =
      GlobalKey<ScaffoldMessengerState>();

  static void showSuccess(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      title: title,
      subtitle: subtitle,
      type: _SnackType.success,
      action: action,
      duration: duration,
    );
  }

  static void showError(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      title: title,
      subtitle: subtitle,
      type: _SnackType.error,
      action: action,
      duration: duration,
    );
  }

  static void showInfo(
    String title, {
    String? subtitle,
    SnackBarAction? action,
    Duration? duration,
  }) {
    _show(
      title: title,
      subtitle: subtitle,
      type: _SnackType.info,
      action: action,
      duration: duration,
    );
  }

  static void showTaskCompletion({
    required String title,
    String? subtitle,
    required SnackBarAction action,
    Duration? duration,
  }) {
    _show(
      title: title,
      subtitle: subtitle,
      type: _SnackType.task,
      action: action,
      duration: duration ?? const Duration(seconds: 6),
    );
  }

  static void _show({
    required String title,
    String? subtitle,
    required _SnackType type,
    SnackBarAction? action,
    Duration? duration,
  }) {
    final messenger = key.currentState;
    if (messenger == null) return;

    final context = key.currentContext;
    final bgColor = context != null
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : null;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: _SnackContent(
            title: title,
            subtitle: subtitle,
            type: type,
          ),
          backgroundColor: bgColor,
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
          duration: duration ?? const Duration(seconds: 4),
          action: action,
        ),
      );
  }
}

class _SnackContent extends StatelessWidget {
  const _SnackContent({
    required this.title,
    this.subtitle,
    required this.type,
  });

  final String title;
  final String? subtitle;
  final _SnackType type;

  Color _dotColor(BuildContext context) {
    return switch (type) {
      _SnackType.success => Colors.green,
      _SnackType.error => Colors.red,
      _SnackType.info || _SnackType.task => Theme.of(context).colorScheme.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = _dotColor(context);

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: dotColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null) ...[
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
