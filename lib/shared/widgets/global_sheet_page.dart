import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/app_spacing.dart';
import 'package:supanotes/shared/widgets/global_sheet_header.dart';

/// Layout for a Family sheet page: a fixed [GlobalSheetHeader] above the
/// feature-owned content.
class GlobalSheetPage extends StatelessWidget {
  const GlobalSheetPage({
    required this.title, required this.child, super.key,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  final String title;
  final Widget child;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlobalSheetHeader(title: title),
          Padding(padding: contentPadding, child: child),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
