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
  bool _fullyHidden = false;

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
    _fade = Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _controller, curve: curve));
    _size = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: curve),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _fullyHidden = true);
        widget.onAnimationComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TaskExitAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);

    final becameComplete =
        widget.isComplete && !oldWidget.isComplete;
    final becameIncomplete =
        !widget.isComplete && oldWidget.isComplete;
    final hideToggledOn =
        widget.hideCompleted && !oldWidget.hideCompleted;
    final hideToggledOff =
        !widget.hideCompleted && oldWidget.hideCompleted;

    if (hideToggledOn && widget.isComplete && !becameComplete) {
      _fullyHidden = false;
      Future.delayed(_exitAnimationDelay, () {
        if (mounted && widget.isComplete && widget.hideCompleted) {
          _controller.forward();
        }
      });
    } else if (hideToggledOff) {
      _fullyHidden = false;
      _controller.reverse();
    } else if (becameComplete && widget.hideCompleted) {
      _fullyHidden = false;
      Future.delayed(_exitAnimationDelay, () {
        if (mounted && widget.isComplete) _controller.forward();
      });
    } else if (becameIncomplete) {
      _fullyHidden = false;
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
    if (_fullyHidden) return const SizedBox(width: 0, height: 0);

    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topLeft,
      child: FadeTransition(opacity: _fade, child: widget.child),
    );
  }
}
