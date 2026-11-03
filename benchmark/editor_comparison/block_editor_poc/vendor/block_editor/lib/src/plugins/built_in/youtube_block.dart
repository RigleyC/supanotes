library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// [BlockPlugin] for [BlockTypes.youtube].
///
/// Stores the YouTube video ID in `attributes['videoId']`. An optional raw
/// URL may be stored in `attributes['url']` — the video ID is parsed from it
/// at serialization time by the host app before storing the node.
///
/// Renders a tappable placeholder. Tapping emits a [CustomBlockEvent] with
/// `eventType: 'youtube_play_requested'` carrying the video ID as payload.
/// The host app opens or embeds the video in response.
///
/// The embed URL is constructed respecting [YouTubeBlockConfig.privacyEnhanced].
/// Configuration is read from [YouTubeBlockConfig] via [BlockEditorScope].
final class YouTubeBlock extends BlockPlugin {
  /// Creates a [YouTubeBlock].
  YouTubeBlock();

  @override
  String get blockType => BlockTypes.youtube;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) {
    return _YouTubeBlockWidget(node: node, onEvent: onEvent);
  }

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'YouTube',
    group: 'Media',
    icon: const Icon(Icons.ondemand_video),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Media';
}

class _YouTubeBlockWidget extends StatelessWidget {
  const _YouTubeBlockWidget({required this.node, required this.onEvent});

  final BlockNode node;
  final void Function(BlockEvent) onEvent;

  static const double _defaultHeight = 200.0;
  static const Color _defaultBackground = Color(0xFF1A1A1A);
  static const Color _foreground = Color(0xFFFFFFFF);
  static const Color _youTubeRed = Color(0xFFFF0000);

  String get _videoId => node.attributes['videoId'] as String? ?? '';

  String embedUrl(bool privacyEnhanced) {
    final domain = privacyEnhanced ? 'youtube-nocookie.com' : 'youtube.com';
    return 'https://www.$domain/embed/$_videoId';
  }

  @override
  Widget build(BuildContext context) {
    final config = BlockEditorScope.maybeOf(context)?.youTubeConfig;
    final privacyEnhanced = config?.privacyEnhanced ?? false;

    if (_videoId.isEmpty) {
      return _placeholder();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onEvent(
        CustomBlockEvent(
          blockId: node.id,
          eventType: 'youtube_play_requested',
          payload: _videoId,
        ),
      ),
      child: Container(
        height: _defaultHeight,
        width: double.infinity,
        color: _defaultBackground,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: 8,
              left: 8,
              child: Text(
                embedUrl(privacyEnhanced),
                style: const TextStyle(color: _foreground, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (config?.showControls ?? true)
              Container(
                width: 56,
                height: 40,
                decoration: BoxDecoration(
                  color: _youTubeRed,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: _foreground,
                  size: 24,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: _defaultHeight,
      color: _defaultBackground,
      child: const Center(
        child: Text('No video ID', style: TextStyle(color: _foreground)),
      ),
    );
  }
}
