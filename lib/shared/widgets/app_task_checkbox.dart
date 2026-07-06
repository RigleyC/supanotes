import 'package:flutter/material.dart';

enum AppTaskCheckboxShape { circle, rounded }

class AppTaskCheckbox extends StatefulWidget {
  const AppTaskCheckbox({
    super.key,
    required this.value,
    this.accentColor,
    this.inactiveColor,
    this.size = 22.0,
    this.shape = AppTaskCheckboxShape.circle,
  });

  final bool value;
  final Color? accentColor;
  final Color? inactiveColor;
  final double size;
  final AppTaskCheckboxShape shape;

  @override
  State<AppTaskCheckbox> createState() => _AppTaskCheckboxState();
}

class _AppTaskCheckboxState extends State<AppTaskCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(
      parent: _controller,
      curve: const ElasticOutCurve(0.8),
    );
    _checkAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
    );
    if (widget.value) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AppTaskCheckbox oldWidget) {
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
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accentColor ?? scheme.primary;
    final inactive = widget.inactiveColor ?? scheme.outline.withValues(alpha: 0.6);

    return Semantics(
      checked: widget.value,
      label: 'Tarefa ${widget.value ? 'concluída' : 'pendente'}',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final scale = 1.0 - (0.15 * (1.0 - _scaleAnim.value));
            final t = _controller.value;
            final fill = Color.lerp(Colors.transparent, accent, t)!;
            final border = Color.lerp(inactive, accent, t)!;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: fill,
                  shape: widget.shape == AppTaskCheckboxShape.circle
                      ? BoxShape.circle
                      : BoxShape.rectangle,
                  borderRadius: widget.shape == AppTaskCheckboxShape.rounded
                      ? BorderRadius.circular(8)
                      : null,
                  border: Border.all(color: border, width: 2),
                ),
                child: _CheckmarkPainter(
                  progress: _checkAnim.value,
                  color: Colors.white,
                ),
              ),
            );
          },
        ),
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
    return CustomPaint(painter: _CheckmarkPaint(progress: progress, color: color));
  }
}

class _CheckmarkPaint extends CustomPainter {
  _CheckmarkPaint({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.45, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.30);

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      final extracted = metric.extractPath(0.0, metric.length * progress);
      canvas.drawPath(extracted, paint);
    }
  }

  @override
  bool shouldRepaint(_CheckmarkPaint oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
