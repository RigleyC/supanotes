import 'package:flutter/material.dart';
import 'snack_view.dart';

class Snack {
  Snack({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.duration,
    this.action,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Duration duration;
  final SnackBarAction? action;

  final GlobalKey<SnackViewState> key = GlobalKey();
}
