import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_editor/block_editor.dart';

void main() {
  group('SlashCommandConfig', () {
    bool selected = false;

    SlashCommandConfig makeConfig({
      String label = 'Code',
      String? group = 'Media',
      String trigger = '/',
      String? description,
    }) {
      return SlashCommandConfig(
        label: label,
        group: group,
        icon: const SizedBox(),
        trigger: trigger,
        description: description,
        onSelected: () => selected = true,
      );
    }

    setUp(() => selected = false);

    test('stores all required fields', () {
      final config = makeConfig();
      expect(config.label, 'Code');
      expect(config.group, 'Media');
      expect(config.trigger, '/');
      expect(config.description, isNull);
    });

    test('default trigger is forward slash', () {
      final config = makeConfig();
      expect(config.trigger, '/');
    });

    test('accepts custom trigger character', () {
      final config = makeConfig(trigger: '@');
      expect(config.trigger, '@');
    });

    test('group may be null', () {
      final config = makeConfig(group: null);
      expect(config.group, isNull);
    });

    test('description is stored when provided', () {
      final config = makeConfig(description: 'Insert a code block');
      expect(config.description, 'Insert a code block');
    });

    test('onSelected callback fires', () {
      final config = makeConfig();
      config.onSelected();
      expect(selected, isTrue);
    });

    test('copyWith replaces label', () {
      final config = makeConfig().copyWith(label: 'Image');
      expect(config.label, 'Image');
    });

    test('copyWith replaces group', () {
      final config = makeConfig().copyWith(group: 'Basic');
      expect(config.group, 'Basic');
    });

    test('copyWith replaces trigger', () {
      final config = makeConfig().copyWith(trigger: '#');
      expect(config.trigger, '#');
    });

    test('copyWith replaces description', () {
      final config = makeConfig().copyWith(description: 'New description');
      expect(config.description, 'New description');
    });

    test('copyWith replaces onSelected', () {
      bool otherSelected = false;
      final config = makeConfig().copyWith(
        onSelected: () => otherSelected = true,
      );
      config.onSelected();
      expect(otherSelected, isTrue);
      expect(selected, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      final config = makeConfig(trigger: '@').copyWith(label: 'Mention');
      expect(config.trigger, '@');
      expect(config.label, 'Mention');
    });

    test('copyWith can set group to null', () {
      final config = makeConfig(group: 'Media').copyWith(group: null);
      expect(config.group, isNull);
    });
  });
}
