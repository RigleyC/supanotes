import 'package:flutter/material.dart';

class ProgressiveFade extends StatelessWidget {
  const ProgressiveFade({
    super.key,
    required this.child,
    this.height = kToolbarHeight,
  });

  final Widget child;
  final double height;

  static const maskColors = [
    Color(0x33FFFFFF),
    Color(0x66FFFFFF),
    Color(0x99FFFFFF),
    Color(0xCCFFFFFF),
    Color(0xFFFFFFFF),
  ];

  static List<double> stopsForBounds({
    required double height,
    required double boundsHeight,
  }) {
    final fadeEnd = boundsHeight == 0
        ? 1.0
        : (height / boundsHeight).clamp(0.0, 1.0);
    return [0, fadeEnd * 0.25, fadeEnd * 0.5, fadeEnd * 0.75, fadeEnd];
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: maskColors,
          stops: stopsForBounds(height: height, boundsHeight: bounds.height),
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}
