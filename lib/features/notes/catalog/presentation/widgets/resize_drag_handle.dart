import 'package:flutter/material.dart';
import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

class ResizeDragHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;

  const ResizeDragHandle({super.key, required this.onDrag});

  @override
  State<ResizeDragHandle> createState() => _ResizeDragHandleState();
}

class _ResizeDragHandleState extends State<ResizeDragHandle> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) {
          widget.onDrag(details.delta.dx);
        },
        child: Container(
          width: DesktopLayoutTokens.resizeHitWidth,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: DesktopLayoutTokens.dividerWidth,
              color: _isHovering
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}
