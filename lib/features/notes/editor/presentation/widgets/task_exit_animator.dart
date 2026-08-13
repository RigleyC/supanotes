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
    if (widget.hideCompleted && widget.isComplete) {
      _controller.value = 1.0;
    }

    final curve = Curves.easeInOutCubic;
    _fade = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: curve));
    _size = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: curve));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAnimationComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TaskExitAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_shouldAnimateWhenHidingCompleted(oldWidget)) {
      _scheduleForwardWhenHidden();
    } else if (_shouldReverseForVisibilityChange(oldWidget)) {
      _controller.reverse();
    } else if (_shouldAnimateCompletedTask(oldWidget)) {
      _scheduleForwardAfterCompletion();
    }
  }

  bool _shouldAnimateWhenHidingCompleted(TaskExitAnimator oldWidget) {
    return widget.hideCompleted &&
        !oldWidget.hideCompleted &&
        widget.isComplete &&
        oldWidget.isComplete;
  }

  bool _shouldReverseForVisibilityChange(TaskExitAnimator oldWidget) {
    final hideToggledOff = !widget.hideCompleted && oldWidget.hideCompleted;
    final becameIncomplete = !widget.isComplete && oldWidget.isComplete;
    return hideToggledOff || becameIncomplete;
  }

  bool _shouldAnimateCompletedTask(TaskExitAnimator oldWidget) {
    return widget.isComplete && !oldWidget.isComplete && widget.hideCompleted;
  }

  void _scheduleForwardWhenHidden() {
    Future.delayed(_exitAnimationDelay, () {
      if (mounted && widget.isComplete && widget.hideCompleted) {
        _controller.forward();
      }
    });
  }

  void _scheduleForwardAfterCompletion() {
    Future.delayed(_exitAnimationDelay, () {
      if (mounted && widget.isComplete) _controller.forward();
    });
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
      alignment: Alignment.topLeft,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}
