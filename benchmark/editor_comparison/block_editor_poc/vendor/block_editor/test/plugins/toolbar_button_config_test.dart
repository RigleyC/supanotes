import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

void main() {
  group('ToolbarButtonConfig', () {
    final icon = const SizedBox();
    BlockNode? capturedNode;

    ToolbarButtonConfig makeConfig({
      Widget? overrideIcon,
      String tooltip = 'Bold',
    }) {
      return ToolbarButtonConfig(
        icon: overrideIcon ?? icon,
        tooltip: tooltip,
        onPressed: (node) => capturedNode = node,
      );
    }

    setUp(() => capturedNode = null);

    test('stores icon, tooltip and onPressed', () {
      final config = makeConfig();
      expect(config.tooltip, 'Bold');
      expect(config.icon, isA<SizedBox>());
    });

    test('onPressed receives the node', () {
      final config = makeConfig();
      final node = BlockNode(type: BlockTypes.paragraph);
      config.onPressed(node);
      expect(capturedNode, node);
    });

    test('copyWith replaces tooltip', () {
      final config = makeConfig().copyWith(tooltip: 'Italic');
      expect(config.tooltip, 'Italic');
    });

    test('copyWith replaces icon', () {
      final newIcon = const Placeholder();
      final config = makeConfig().copyWith(icon: newIcon);
      expect(config.icon, isA<Placeholder>());
    });

    test('copyWith replaces onPressed', () {
      BlockNode? other;
      final config = makeConfig().copyWith(onPressed: (n) => other = n);
      final node = BlockNode(type: BlockTypes.paragraph);
      config.onPressed(node);
      expect(other, node);
      expect(capturedNode, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      final config = makeConfig(
        tooltip: 'Strike',
      ).copyWith(icon: const Placeholder());
      expect(config.tooltip, 'Strike');
    });
  });
}
