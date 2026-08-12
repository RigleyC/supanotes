import 'package:flutter/material.dart';

import 'global_sheet_header.dart';

/// Layout for a Family sheet page: a fixed [GlobalSheetHeader] above the
/// feature-owned content.
class GlobalSheetPage extends StatelessWidget {
  const GlobalSheetPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlobalSheetHeader(title: title),
          child,
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Layout for a page whose child owns its scrollable content.
class GlobalSheetScrollablePage extends StatelessWidget {
  const GlobalSheetScrollablePage({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlobalSheetHeader(title: title),
                Flexible(fit: FlexFit.loose, child: child),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
