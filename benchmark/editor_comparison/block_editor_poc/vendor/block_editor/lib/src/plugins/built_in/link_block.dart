library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// [BlockPlugin] for [BlockTypes.link].
///
/// Stores link metadata in [BlockNode.attributes]:
///
/// - `url` — the destination URL.
/// - `displayText` — the label shown to the user. Falls back to url when absent.
///
/// Renders a tappable row. When tapped, [LinkBlockConfig.onOpen] is called
/// if provided via [BlockEditorScope]. When no callback is present a
/// [CustomBlockEvent] with `eventType: 'link_open_requested'` is emitted
/// carrying the URL as payload.
///
/// Configuration is read from [LinkBlockConfig] via [BlockEditorScope].
final class LinkBlock extends BlockPlugin {
  /// Creates a [LinkBlock].
  LinkBlock();

  @override
  String get blockType => BlockTypes.link;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) {
    return _LinkBlockWidget(node: node, onEvent: onEvent);
  }

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Link',
    group: 'Basic',
    icon: const Icon(Icons.link),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Basic';
}

class _LinkBlockWidget extends StatelessWidget {
  const _LinkBlockWidget({required this.node, required this.onEvent});

  final BlockNode node;
  final void Function(BlockEvent) onEvent;

  static const Color _background = Color(0xFFF0F7FF);
  static const Color _urlColor = Color(0xFF0070F3);
  static const Color _labelColor = Color(0xFF222222);
  static const Color _subtextColor = Color(0xFF888888);

  String get _url => node.attributes['url'] as String? ?? '';
  String get _displayText => node.attributes['displayText'] as String? ?? _url;

  void _handleTap(BuildContext context, LinkBlockConfig? config) {
    if (_url.isEmpty) return;
    if (config?.onOpen != null) {
      config!.onOpen!(_url);
    } else {
      onEvent(
        CustomBlockEvent(
          blockId: node.id,
          eventType: 'link_open_requested',
          payload: _url,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = BlockEditorScope.maybeOf(context)?.linkConfig;

    if (_url.isEmpty) {
      return _placeholder();
    }

    return GestureDetector(
      onTap: () => _handleTap(context, config),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _urlColor.withAlpha(60)),
        ),
        child: Row(
          children: [
            const Icon(
              IconData(0xe157, fontFamily: 'MaterialIcons'),
              color: _urlColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _displayText,
                    style: const TextStyle(
                      color: _labelColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_displayText != _url)
                    Text(
                      _url,
                      style: const TextStyle(
                        color: _subtextColor,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'No URL',
        style: TextStyle(color: _subtextColor, fontSize: 14),
      ),
    );
  }
}
