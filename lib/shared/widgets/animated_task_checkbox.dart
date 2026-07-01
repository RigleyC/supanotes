import 'package:flutter/material.dart';

class AnimatedTaskCheckbox extends StatefulWidget {
  const AnimatedTaskCheckbox({
    super.key,
    required this.size,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.checkmarkColor,
  });

  final double size;
  final bool value;
  final Color activeColor;
  final Color inactiveColor;
  final Color checkmarkColor;

  @override
  State<AnimatedTaskCheckbox> createState() => _AnimatedTaskCheckboxState();
}

class _AnimatedTaskCheckboxState extends State<AnimatedTaskCheckbox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: const ElasticOutCurve(0.8),
    );

    _checkAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
    );

    if (widget.value) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AnimatedTaskCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = 1.0 - (0.15 * (1.0 - _scaleAnim.value));
            final checkProgress = _checkAnim.value;

            return Transform.scale(
              scale: scale,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: widget.value ? widget.activeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.value
                        ? widget.activeColor
                        : widget.inactiveColor,
                    width: 2,
                  ),
                ),
                child: _CheckmarkPainter(
                  progress: checkProgress,
                  color: widget.checkmarkColor,
                ),
              ),
            );
          },
        ),
      );
  }
}

class _CheckmarkPainter extends StatelessWidget {
  const _CheckmarkPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckmarkPaint(progress: progress, color: color),
    );
  }
}

class _CheckmarkPaint extends CustomPainter {
  _CheckmarkPaint({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final start = Offset(size.width * 0.22, size.height * 0.52);
    final mid = Offset(size.width * 0.45, size.height * 0.72);
    final end = Offset(size.width * 0.78, size.height * 0.30);

    path.moveTo(start.dx, start.dy);
    path.lineTo(mid.dx, mid.dy);
    path.lineTo(end.dx, end.dy);

    if (progress <= 0.0) return;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final extractPath = metric.extractPath(0.0, metric.length * progress);
      canvas.drawPath(extractPath, paint);
    }
  }

  @override
  bool shouldRepaint(_CheckmarkPaint oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
