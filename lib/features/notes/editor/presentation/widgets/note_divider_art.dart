import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One of the hand-drawn divider illustrations, chosen by [dividerIndex].
class NoteDividerArt extends StatelessWidget {
  const NoteDividerArt({super.key, this.dividerIndex});

  /// Number of divider SVG assets in `assets/dividers`.
  static const count = 35;

  /// 1-based asset index; out-of-range values are clamped.
  final int? dividerIndex;

  @override
  Widget build(BuildContext context) {
    final index = (dividerIndex ?? 1).clamp(1, count);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 16,
        width: double.infinity,
        child: RepaintBoundary(
          child: SvgPicture.asset(
            'assets/dividers/divider_${index.toString().padLeft(2, '0')}.svg',
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
    );
  }
}
