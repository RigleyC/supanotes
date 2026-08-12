import 'package:flutter/material.dart';

import 'global_sheet_header.dart';

/// Layout for a Family sheet page: a fixed [GlobalSheetHeader] above a bounded
/// content slot. The child receives a bounded viewport, so a feature-owned
/// `ListView` or `CustomScrollView` scrolls below the fixed header.
class GlobalSheetPage extends StatelessWidget {
  const GlobalSheetPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: constraints.maxHeight,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlobalSheetHeader(title: title),
                Expanded(child: child),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
