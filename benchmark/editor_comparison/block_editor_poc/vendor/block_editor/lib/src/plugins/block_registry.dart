library;

import 'package:flutter/widgets.dart';
import 'package:block_editor/block_editor.dart';

/// The central registry that maps block type strings to [BlockPlugin]
/// implementations.
///
/// [BlockRegistry] is a singleton. Access it via [BlockRegistry.instance].
/// Built-in plugins are pre-registered during initialisation. External
/// plugins are registered via [register] at app startup.
///
/// There is no runtime distinction between built-in and external plugins
/// once registered. Both are resolved identically through [resolve].
final class BlockRegistry {
  BlockRegistry._() {
    _registerBuiltIns();
  }

  static final BlockRegistry instance = BlockRegistry._();

  final Map<String, BlockPlugin> _plugins = {};

  void _registerBuiltIns() {
    for (final plugin in _builtInPlugins) {
      _plugins[plugin.blockType] = plugin;
    }
  }

  static final List<BlockPlugin> _builtInPlugins = [
    ParagraphBlock(),
    H1Block(),
    H2Block(),
    H3Block(),
    BulletListBlock(),
    NumberedListBlock(),
    TodoBlock(),
    QuoteBlock(),
    DividerBlock(),
    ImageBlock(),
    VideoBlock(),
    YouTubeBlock(),
    FileBlock(),
    CodeBlock(),
    CalloutBlock(),
    LinkBlock(),
  ];

  /// Registers [plugin] for its declared [BlockPlugin.blockType].
  ///
  /// If a plugin is already registered for that type it is replaced.
  /// Built-in plugins may be replaced by calling [register] with a plugin
  /// whose [BlockPlugin.blockType] matches a [BlockTypes] constant.
  void register(BlockPlugin plugin) {
    _plugins[plugin.blockType] = plugin;
  }

  /// Registers each plugin in [plugins] for its declared
  /// [BlockPlugin.blockType].
  ///
  /// If multiple plugins in [plugins] share the same block type, the last
  /// occurrence wins. If a plugin is already registered for a given type,
  /// it is replaced by the corresponding plugin in [plugins].
  ///
  /// Built-in plugins may be replaced by including a plugin in [plugins]
  /// whose [BlockPlugin.blockType] matches a [BlockTypes] constant.
  ///
  /// This is a convenience method for bulk registration and is equivalent
  /// to calling [register] for each plugin in iteration order.
  void registerAll(List<BlockPlugin> plugins) {
    for (final plugin in plugins) {
      _plugins[plugin.blockType] = plugin;
    }
  }

  /// Returns the [BlockPlugin] registered for [blockType], or null if none
  /// is registered.
  BlockPlugin? resolve(String blockType) => _plugins[blockType];

  /// Returns all registered [BlockPlugin] instances.
  Iterable<BlockPlugin> get plugins => _plugins.values;

  /// Builds the widget for [node] using its registered plugin.
  ///
  /// Returns an [UnknownBlock] when no plugin is registered for node.type.
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) {
    final plugin = resolve(node.type);
    if (plugin == null) {
      return UnknownBlock(blockId: node.id, type: node.type);
    }
    return plugin.build(node, selection, onEvent);
  }

  /// Serializes [node] using its registered plugin.
  ///
  /// Returns an empty map when no plugin is registered for node.type.
  Map<String, dynamic> serialize(BlockNode node) {
    return resolve(node.type)?.serialize(node) ?? {};
  }

  /// Deserializes a [BlockNode] from [json] using the plugin registered for
  /// the type value found at `json['type']`.
  ///
  /// Returns null when no plugin is registered for that type.
  BlockNode? deserialize(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == null) return null;
    return resolve(type)?.deserialize(json);
  }

  /// Returns all [SlashCommandConfig] entries across every registered plugin
  /// that declares one, grouped by [SlashCommandConfig.trigger].
  Map<String, List<SlashCommandConfig>> slashCommands() {
    final result = <String, List<SlashCommandConfig>>{};
    for (final plugin in _plugins.values) {
      final config = plugin.slashCommandItem();
      if (config == null) continue;
      result.putIfAbsent(config.trigger, () => []).add(config);
    }
    return result;
  }

  /// Returns all [ToolbarButtonConfig] entries across every registered plugin
  /// that declares one.
  List<ToolbarButtonConfig> toolbarButtons() {
    return _plugins.values
        .map((p) => p.toolbarButton())
        .whereType<ToolbarButtonConfig>()
        .toList();
  }
}
