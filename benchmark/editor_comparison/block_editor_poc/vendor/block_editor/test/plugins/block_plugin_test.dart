import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

class _StubPlugin extends BlockPlugin {
  _StubPlugin({
    required this.blockType,
    this.stubToolbarButton,
    this.stubSlashCommandItem,
    this.stubSlashCommandGroup,
  });

  @override
  final String blockType;

  final ToolbarButtonConfig? stubToolbarButton;
  final SlashCommandConfig? stubSlashCommandItem;
  final String? stubSlashCommandGroup;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => const SizedBox();

  @override
  Map<String, dynamic> serialize(BlockNode node) => {'type': blockType};

  @override
  BlockNode deserialize(Map<String, dynamic> json) =>
      BlockNode(type: blockType);

  @override
  ToolbarButtonConfig? toolbarButton() => stubToolbarButton;

  @override
  SlashCommandConfig? slashCommandItem() => stubSlashCommandItem;

  @override
  String? slashCommandGroup() => stubSlashCommandGroup;
}

void main() {
  group('BlockPlugin interface defaults', () {
    final plugin = _StubPlugin(blockType: 'stub');

    test('toolbarButton returns null by default', () {
      expect(plugin.toolbarButton(), isNull);
    });

    test('slashCommandItem returns null by default', () {
      expect(plugin.slashCommandItem(), isNull);
    });

    test('slashCommandGroup returns null by default', () {
      expect(plugin.slashCommandGroup(), isNull);
    });
  });

  group('BlockPlugin contract', () {
    test('blockType is accessible', () {
      final plugin = _StubPlugin(blockType: 'my_custom_block');
      expect(plugin.blockType, 'my_custom_block');
    });

    test('build returns a widget', () {
      final plugin = _StubPlugin(blockType: 'stub');
      final node = BlockNode(type: 'stub');
      final widget = plugin.build(node, EditorSelection.none, (_) {});
      expect(widget, isA<Widget>());
    });

    test('serialize returns a map containing the type', () {
      final plugin = _StubPlugin(blockType: 'stub');
      final node = BlockNode(type: 'stub');
      final json = plugin.serialize(node);
      expect(json['type'], 'stub');
    });

    test('deserialize returns a BlockNode with correct type', () {
      final plugin = _StubPlugin(blockType: 'stub');
      final node = plugin.deserialize({'type': 'stub'});
      expect(node.type, 'stub');
    });

    test('toolbarButton returns config when provided', () {
      final config = ToolbarButtonConfig(
        icon: const SizedBox(),
        tooltip: 'Test',
        onPressed: (_) {},
      );
      final plugin = _StubPlugin(blockType: 'stub', stubToolbarButton: config);
      expect(plugin.toolbarButton(), config);
    });

    test('slashCommandItem returns config when provided', () {
      final config = SlashCommandConfig(
        label: 'Stub',
        group: 'Test',
        icon: const SizedBox(),
        onSelected: () {},
      );
      final plugin = _StubPlugin(
        blockType: 'stub',
        stubSlashCommandItem: config,
      );
      expect(plugin.slashCommandItem(), config);
    });

    test('slashCommandGroup returns group when provided', () {
      final plugin = _StubPlugin(
        blockType: 'stub',
        stubSlashCommandGroup: 'Custom',
      );
      expect(plugin.slashCommandGroup(), 'Custom');
    });
  });
}
