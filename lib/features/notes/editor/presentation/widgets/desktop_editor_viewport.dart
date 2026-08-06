import 'package:flutter/material.dart';

import 'package:supanotes/shared/theme/desktop_layout_tokens.dart';

double desktopEditorSidePaddingForWidth(double availableWidth) {
  return ((availableWidth - DesktopLayoutTokens.editorMaxWidth) / 2)
      .clamp(
        DesktopLayoutTokens.editorSidePaddingMin,
        DesktopLayoutTokens.editorSidePaddingMax,
      )
      .toDouble();
}

/// Resolved desktop document metrics provided by [DesktopEditorViewport].
///
/// The viewport owns the responsive geometry. The editor consumes this scope
/// when it creates the stylesheet for the document.
class DesktopEditorLayoutScope extends InheritedWidget {
  final EdgeInsets documentPadding;

  const DesktopEditorLayoutScope({
    super.key,
    required this.documentPadding,
    required super.child,
  });

  static DesktopEditorLayoutScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DesktopEditorLayoutScope>();
  }

  @override
  bool updateShouldNotify(DesktopEditorLayoutScope oldWidget) {
    return oldWidget.documentPadding != documentPadding;
  }
}

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
        child: SizedBox(
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final sidePadding = desktopEditorSidePaddingForWidth(
                availableWidth,
              );
              final viewportHeight = MediaQuery.sizeOf(context).height;

              return DesktopEditorLayoutScope(
                documentPadding: EdgeInsets.only(
                  left: sidePadding,
                  right: sidePadding,
                  top: DesktopLayoutTokens.editorTopPadding,
                  bottom: DesktopLayoutTokens.editorBottomPaddingForHeight(
                    viewportHeight,
                  ),
                ),
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }
}
