import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ThemeSvg extends StatelessWidget {
  const ThemeSvg(
    this.asset, {
    super.key,
    this.size = 24,
  });

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        isDark ? Colors.white : Colors.black,
        BlendMode.srcIn,
      ),
    );
  }
}
