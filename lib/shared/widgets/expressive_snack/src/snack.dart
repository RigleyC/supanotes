import 'package:flutter/material.dart';
import 'package:supanotes/shared/widgets/expressive_snack/src/snack_view.dart';

class Snack {
  Snack({
    required this.title,
    required this.icon, required this.duration, this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Duration duration;
  SnackBarAction? action;

  final GlobalKey<SnackViewState> key = GlobalKey();
}
