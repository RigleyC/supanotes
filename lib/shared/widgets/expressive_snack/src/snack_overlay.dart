import 'package:flutter/material.dart';
import 'snack.dart';
import 'snack_view.dart';

class SnackOverlay extends StatefulWidget {
  SnackOverlay({required this.child}) : super(key: _key);

  final Widget child;

  static void refresh() => _key.currentState?._refresh();

  static Snack add(Snack snack) {
    final state = _key.currentState;
    if (state == null) return snack;

    final index = state._snacks.indexWhere(
      (s) => s.title == snack.title && s.subtitle == snack.subtitle && s.icon == snack.icon,
    );

    if (index != -1) {
      final existing = state._snacks[index];
      existing.action = snack.action;
      return existing;
    }

    state._add(snack);
    return snack;
  }

  static void remove(Snack snack) => _key.currentState?._remove(snack);

  static final GlobalKey<_SnackOverlayState> _key = GlobalKey();

  @override
  State<SnackOverlay> createState() => _SnackOverlayState();
}

class _SnackOverlayState extends State<SnackOverlay> {
  final List<Snack> _snacks = [];

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _add(Snack snack) {
    if (mounted) {
      setState(() {
        _snacks.insert(0, snack);
      });
    }
  }

  void _remove(Snack snack) {
    if (mounted) {
      setState(() {
        _snacks.remove(snack);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          bottom: safeArea.bottom + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            verticalDirection: VerticalDirection.up,
            children: [
              for (var i = 0; i < _snacks.length && i < 3; i++)
                SnackView(
                  key: _snacks[i].key,
                  snack: _snacks[i],
                  depth: i,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
