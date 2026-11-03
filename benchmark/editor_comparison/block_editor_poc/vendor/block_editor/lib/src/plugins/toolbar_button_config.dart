library;

import 'package:flutter/widgets.dart';
import 'package:block_editor/block_editor.dart';

/// Describes the toolbar button a [BlockPlugin] contributes to the formatting
/// toolbar.
///
/// Returned by [BlockPlugin.toolbarButton]. When null is returned the plugin
/// contributes no button.
@immutable
final class ToolbarButtonConfig {
  /// Creates a [ToolbarButtonConfig].
  ///
  /// [icon] is the widget displayed as the button face.
  ///
  /// [tooltip] is the accessible label shown on long-press or hover.
  ///
  /// [onPressed] is called with the current [BlockNode] when the button is
  /// activated. The plugin uses the node to read block state and emits a
  /// [BlockEvent] through its own onEvent handle to request mutations.
  const ToolbarButtonConfig({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  /// The widget displayed as the button face.
  final Widget icon;

  /// The accessible label shown on long-press or hover.
  final String tooltip;

  /// Called with the current [BlockNode] when the button is activated.
  final void Function(BlockNode node) onPressed;

  /// Returns a copy of this config with the given fields replaced.
  ToolbarButtonConfig copyWith({
    Widget? icon,
    String? tooltip,
    void Function(BlockNode node)? onPressed,
  }) {
    return ToolbarButtonConfig(
      icon: icon ?? this.icon,
      tooltip: tooltip ?? this.tooltip,
      onPressed: onPressed ?? this.onPressed,
    );
  }
}
