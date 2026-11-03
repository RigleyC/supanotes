library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// [BlockPlugin] for [BlockTypes.video].
///
/// Supports two source variants stored in [BlockNode.attributes]:
///
/// - `source: 'network'` — a video at `attributes['url']`.
/// - `source: 'local'` — a video at `attributes['path']`.
///
/// Because Flutter has no built-in video player, this block renders a
/// tappable preview placeholder. When the user taps it, a [CustomBlockEvent]
/// with `eventType: 'video_play_requested'` is emitted carrying the URL or
/// path as payload. The host app wires its own video player in response.
///
/// Configuration is read from [VideoBlockConfig] via [BlockEditorScope].
final class VideoBlock extends BlockPlugin {
  /// Creates a [VideoBlock].
  VideoBlock();

  @override
  String get blockType => BlockTypes.video;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) {
    return _VideoBlockWidget(node: node, onEvent: onEvent);
  }

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Video',
    group: 'Media',
    icon: const Icon(Icons.videocam),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Media';
}

class _VideoBlockWidget extends StatelessWidget {
  const _VideoBlockWidget({required this.node, required this.onEvent});

  final BlockNode node;
  final void Function(BlockEvent) onEvent;

  static const double _defaultHeight = 200.0;
  static const Color _defaultBackground = Color(0xFF1A1A1A);
  static const Color _iconColor = Color(0xFFFFFFFF);

  String get _source => node.attributes['source'] as String? ?? 'network';
  String get _url => node.attributes['url'] as String? ?? '';
  String get _path => node.attributes['path'] as String? ?? '';

  String get _resolvedPath => _source == 'local' ? _path : _url;

  @override
  Widget build(BuildContext context) {
    final config = BlockEditorScope.maybeOf(context)?.videoConfig;

    if (_resolvedPath.isEmpty) {
      return _placeholder();
    }

    return GestureDetector(
      onTap: () => onEvent(
        CustomBlockEvent(
          blockId: node.id,
          eventType: 'video_play_requested',
          payload: _resolvedPath,
        ),
      ),
      child: _buildPreview(context, config),
    );
  }

  Widget _buildPreview(BuildContext context, VideoBlockConfig? config) {
    return Container(
      height: _defaultHeight,
      width: double.infinity,
      color: _defaultBackground,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (config?.showControls ?? true)
            const _PlayButton(color: _iconColor),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: _defaultHeight,
      color: _defaultBackground,
      child: const Center(
        child: Text('No video', style: TextStyle(color: _iconColor)),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withAlpha(60),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow, color: color, size: 32),
    );
  }
}
