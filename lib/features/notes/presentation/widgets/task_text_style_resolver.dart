import 'package:flutter/material.dart';

TextStyle resolveTaskTextStyle(
  TextStyle baseStyle,
  Color defaultColor,
  bool isComplete,
) {
  final color = baseStyle.color ?? defaultColor;
  if (!isComplete) return baseStyle.copyWith(color: color);
  return baseStyle.copyWith(
    color: color.withValues(alpha: 0.5),
    decoration: TextDecoration.lineThrough,
  );
}
