library;

import 'package:flutter/widgets.dart';
import 'package:block_editor/block_editor.dart';

/// Ambient editor data inherited by all widgets in the block editor tree.
///
/// [BlockEditorScope] is placed at the root of the editor widget tree by
/// [BlockEditorWidget]. Any widget in the subtree can read scope data via
/// [BlockEditorScope.maybeOf] without requiring intermediate widgets to
/// forward parameters explicitly.
///
/// The scope carries the variable resolution map, the read-only flag, and
/// optional configuration objects for every built-in block type. New ambient
/// fields are added here as the editor grows — no plugin or intermediate
/// widget API is ever changed to thread ambient data.
class BlockEditorScope extends InheritedWidget {
  /// Creates a [BlockEditorScope] wrapping [child].
  ///
  /// All parameters are optional and default to their inactive states.
  /// Supply only the configuration objects for the blocks you want to
  /// customise — unset configs cause each block to use its own defaults.
  const BlockEditorScope({
    super.key,
    required super.child,
    this.variables = const {},
    this.readOnly = false,
    this.imageConfig,
    this.videoConfig,
    this.youTubeConfig,
    this.fileConfig,
    this.codeConfig,
    this.calloutConfig,
    this.linkConfig,
  });

  /// The variable resolution map for inline variable embeds.
  ///
  /// When a variable name has no entry, the raw `{{variableName}}` placeholder
  /// is displayed. The document is never modified during resolution.
  final Map<String, String> variables;

  /// Whether the editor is in read-only viewer mode.
  final bool readOnly;

  /// Optional configuration for image blocks.
  final ImageBlockConfig? imageConfig;

  /// Optional configuration for video blocks.
  final VideoBlockConfig? videoConfig;

  /// Optional configuration for YouTube embed blocks.
  final YouTubeBlockConfig? youTubeConfig;

  /// Optional configuration for file attachment blocks.
  final FileBlockConfig? fileConfig;

  /// Optional configuration for code blocks.
  final CodeBlockConfig? codeConfig;

  /// Optional configuration for callout blocks.
  final CalloutBlockConfig? calloutConfig;

  /// Optional configuration for link blocks.
  final LinkBlockConfig? linkConfig;

  /// Returns the nearest [BlockEditorScope] ancestor, or null if none exists.
  static BlockEditorScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BlockEditorScope>();
  }

  @override
  bool updateShouldNotify(BlockEditorScope oldWidget) {
    return variables != oldWidget.variables ||
        readOnly != oldWidget.readOnly ||
        imageConfig != oldWidget.imageConfig ||
        videoConfig != oldWidget.videoConfig ||
        youTubeConfig != oldWidget.youTubeConfig ||
        fileConfig != oldWidget.fileConfig ||
        codeConfig != oldWidget.codeConfig ||
        calloutConfig != oldWidget.calloutConfig ||
        linkConfig != oldWidget.linkConfig;
  }
}
