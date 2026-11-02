library;

import 'package:flutter/material.dart';
import 'package:block_editor/block_editor.dart';

/// [BlockPlugin] for [BlockTypes.image].
///
/// Supports three source variants stored in [BlockNode.attributes]:
///
/// - `source: 'network'` — renders a network image from `attributes['url']`.
/// - `source: 'local'` — renders a local file image from `attributes['path']`.
/// - `source: 'upload_pending'` — shows a loading indicator while the host
///   app performs an upload. The block emits a [CustomBlockEvent] with
///   `eventType: 'image_upload_requested'` carrying the local path as payload.
///
/// Configuration is read from [ImageBlockConfig] via [BlockEditorScope].
/// When no config is present the block uses internal defaults.
final class ImageBlock extends BlockPlugin {
  /// Creates an [ImageBlock].
  ImageBlock();

  @override
  String get blockType => BlockTypes.image;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) {
    return _ImageBlockWidget(node: node, onEvent: onEvent);
  }

  @override
  Map<String, dynamic> serialize(BlockNode node) => node.toJson();

  @override
  BlockNode deserialize(Map<String, dynamic> json) => BlockNode.fromJson(json);

  @override
  SlashCommandConfig slashCommandItem() => SlashCommandConfig(
    label: 'Image',
    group: 'Media',
    icon: const Icon(Icons.image_outlined),
    onSelected: () {},
  );

  @override
  String slashCommandGroup() => 'Media';
}

class _ImageBlockWidget extends StatelessWidget {
  const _ImageBlockWidget({required this.node, required this.onEvent});

  final BlockNode node;
  final void Function(BlockEvent) onEvent;

  static const Color _defaultBackground = Color(0xFFF5F5F5);
  static const double _defaultHeight = 200.0;

  @override
  Widget build(BuildContext context) {
    final config = BlockEditorScope.maybeOf(context)?.imageConfig;
    final source = node.attributes['source'] as String? ?? 'network';
    final fit = config?.fit ?? BoxFit.contain;
    final scale = config?.scale ?? 1.0;
    final borderRadius = config?.borderRadius ?? BorderRadius.zero;

    return ClipRRect(
      borderRadius: borderRadius,
      child: Transform.scale(
        scale: scale,
        child: _buildContent(context, source, fit, config),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    String source,
    BoxFit fit,
    ImageBlockConfig? config,
  ) {
    switch (source) {
      case 'network':
        final url = node.attributes['url'] as String? ?? '';
        if (url.isEmpty) return _placeholder();
        return Image.network(
          url,
          fit: fit,
          height: _defaultHeight,
          errorBuilder: (ctx, error, _) =>
              config?.onError?.call(ctx, error) ?? _errorWidget(),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return config?.onLoading?.call(ctx) ?? _loadingWidget();
          },
        );

      case 'local':
        final path = node.attributes['path'] as String? ?? '';
        if (path.isEmpty) return _placeholder();
        onEvent(
          CustomBlockEvent(
            blockId: node.id,
            eventType: 'image_upload_requested',
            payload: path,
          ),
        );
        return config?.onLoading?.call(context) ?? _loadingWidget();

      case 'upload_pending':
        return config?.onLoading?.call(context) ?? _loadingWidget();

      default:
        return _placeholder();
    }
  }

  Widget _placeholder() {
    return Container(
      height: _defaultHeight,
      color: _defaultBackground,
      child: const Center(child: Text('No image')),
    );
  }

  Widget _loadingWidget() {
    return Container(
      height: _defaultHeight,
      color: _defaultBackground,
      child: const Center(child: Text('Loading…')),
    );
  }

  Widget _errorWidget() {
    return Container(
      height: _defaultHeight,
      color: _defaultBackground,
      child: const Center(child: Text('Failed to load image')),
    );
  }
}
