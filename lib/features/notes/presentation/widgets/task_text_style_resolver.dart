import 'package:flutter/material.dart';

TextStyle resolveTaskTextStyle(
  Set<Object> attributions,
  TextStyle Function(Set<Object>) baseBuilder,
  TextStyle baseColor,
  bool isComplete,
) {
  final style = baseBuilder(attributions);
  final color = style.color ?? baseColor;
  if (!isComplete) return style.copyWith(color: color);
  return style.copyWith(
    color: color.withValues(alpha: 0.5),
    decoration: TextDecoration.lineThrough,
  );
}
