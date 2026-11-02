import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

class _StubPlugin extends BlockPlugin {
  _StubPlugin({
    required this.blockType,
    this.stubToolbarButton,
    this.stubSlashCommandItem,
  });

  @override
  final String blockType;

  final ToolbarButtonConfig? stubToolbarButton;
  final SlashCommandConfig? stubSlashCommandItem;

  @override
  Widget build(
    BlockNode node,
    EditorSelection selection,
    void Function(BlockEvent) onEvent,
  ) => const SizedBox(key: ValueKey('stub_widget'));

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
  String? slashCommandGroup() => null;
}

void main() {
  group('BlockRegistry', () {
    setUp(() {
      BlockRegistry.instance.register(_StubPlugin(blockType: 'stub_a'));
    });

    test('resolve returns plugin after registration', () {
      expect(BlockRegistry.instance.resolve('stub_a'), isNotNull);
    });

    test('resolve returns null for unregistered type', () {
      expect(BlockRegistry.instance.resolve('__nonexistent__'), isNull);
    });

    test('registering same type overwrites previous plugin', () {
      final first = _StubPlugin(blockType: 'overwrite_test');
      final second = _StubPlugin(blockType: 'overwrite_test');
      BlockRegistry.instance.register(first);
      BlockRegistry.instance.register(second);
      expect(
        identical(BlockRegistry.instance.resolve('overwrite_test'), second),
        isTrue,
      );
    });

    test(
      'registerAll registers multiple plugins and overwrites duplicates in order',
      () {
        final first = _StubPlugin(blockType: 'multi_a');
        final second = _StubPlugin(blockType: 'multi_b');
        final overwrite1 = _StubPlugin(blockType: 'multi_overwrite');
        final overwrite2 = _StubPlugin(blockType: 'multi_overwrite');

        BlockRegistry.instance.registerAll([
          first,
          second,
          overwrite1,
          overwrite2,
        ]);

        expect(BlockRegistry.instance.resolve('multi_a'), same(first));
        expect(BlockRegistry.instance.resolve('multi_b'), same(second));

        expect(
          identical(
            BlockRegistry.instance.resolve('multi_overwrite'),
            overwrite2,
          ),
          isTrue,
        );
      },
    );

    test('build returns UnknownBlock for unregistered type', () {
      final node = BlockNode(type: '__unknown_xyz__');
      final widget = BlockRegistry.instance.build(
        node,
        EditorSelection.none,
        (_) {},
      );
      expect(widget, isA<UnknownBlock>());
    });

    test('serialize returns empty map for unregistered type', () {
      final node = BlockNode(type: '__unknown_xyz__');
      expect(BlockRegistry.instance.serialize(node), isEmpty);
    });

    test('deserialize returns null when type is missing', () {
      expect(BlockRegistry.instance.deserialize({}), isNull);
    });

    test('deserialize returns null for unregistered type', () {
      expect(
        BlockRegistry.instance.deserialize({'type': '__unknown_xyz__'}),
        isNull,
      );
    });

    test('slashCommands groups entries by trigger character', () {
      BlockRegistry.instance.register(
        _StubPlugin(
          blockType: 'slash_block',
          stubSlashCommandItem: SlashCommandConfig(
            label: 'Slash',
            group: 'Basic',
            icon: const SizedBox(),
            trigger: '/',
            onSelected: () {},
          ),
        ),
      );
      BlockRegistry.instance.register(
        _StubPlugin(
          blockType: 'mention_block',
          stubSlashCommandItem: SlashCommandConfig(
            label: 'Mention',
            group: 'People',
            icon: const SizedBox(),
            trigger: '@',
            onSelected: () {},
          ),
        ),
      );
      final commands = BlockRegistry.instance.slashCommands();
      expect(commands.containsKey('/'), isTrue);
      expect(commands.containsKey('@'), isTrue);
      expect(commands['/']!.any((c) => c.label == 'Slash'), isTrue);
      expect(commands['@']!.any((c) => c.label == 'Mention'), isTrue);
    });

    test('slashCommands excludes plugins with no slash command', () {
      BlockRegistry.instance.register(_StubPlugin(blockType: 'no_slash'));
      final commands = BlockRegistry.instance.slashCommands();
      final allConfigs = commands.values.expand((e) => e);
      expect(allConfigs.any((c) => c.label == 'no_slash'), isFalse);
    });

    test('toolbarButtons returns configs from plugins that declare one', () {
      final config = ToolbarButtonConfig(
        icon: const SizedBox(),
        tooltip: 'Stub A',
        onPressed: (_) {},
      );
      BlockRegistry.instance.register(
        _StubPlugin(blockType: 'toolbar_block', stubToolbarButton: config),
      );
      final buttons = BlockRegistry.instance.toolbarButtons();
      expect(buttons.any((b) => b.tooltip == 'Stub A'), isTrue);
    });

    test('toolbarButtons excludes plugins with no toolbar button', () {
      BlockRegistry.instance.register(_StubPlugin(blockType: 'no_toolbar'));
      final buttons = BlockRegistry.instance.toolbarButtons();
      expect(buttons.any((b) => b.tooltip == 'no_toolbar'), isFalse);
    });
  });
}
