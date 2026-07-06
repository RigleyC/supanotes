import 'package:flutter/material.dart';

const Duration _exitAnimationDelay = Duration(milliseconds: 300);
const Duration _exitAnimationDuration = Duration(milliseconds: 350);

class TaskExitAnimator extends StatefulWidget {
  const TaskExitAnimator({
    super.key,
    required this.hideCompleted,
    required this.isComplete,
    required this.onAnimationComplete,
    required this.child,
  });

  final bool hideCompleted;
  final bool isComplete;
  final VoidCallback? onAnimationComplete;
  final Widget child;

  @override
  State<TaskExitAnimator> createState() => _TaskExitAnimatorState();
}

class _TaskExitAnimatorState extends State<TaskExitAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _size;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _exitAnimationDuration,
    );
    _fade = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _size = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });

    if (widget.hideCompleted && widget.isComplete) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant TaskExitAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hideCompleted) return;

    final becameComplete =
        widget.isComplete && !oldWidget.isComplete;
    final becameIncomplete =
        !widget.isComplete && oldWidget.isComplete;

    if (becameComplete) {
      Future.delayed(_exitAnimationDelay, () {
        if (mounted && widget.isComplete) _controller.forward();
      });
    } else if (becameIncomplete) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _size,
      axisAlignment: 0.0,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}
