import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

/// Keeps the desktop document column readable while letting the editor use
/// the remaining shell space for scrolling and overlays.
class DesktopEditorViewport extends StatelessWidget {
  final Widget child;

  const DesktopEditorViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth:
              DesktopLayoutTokens.editorMaxWidth +
              (DesktopLayoutTokens.editorSidePaddingMax * 2),
        ),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
