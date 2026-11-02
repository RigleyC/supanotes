import 'package:block_editor/block_editor.dart';
import 'package:test/test.dart';

void main() {
  group('InlineAttributes', () {
    test('const empty constructor produces all-null fields', () {
      const attrs = InlineAttributes();
      expect(attrs.bold, isNull);
      expect(attrs.italic, isNull);
      expect(attrs.underline, isNull);
      expect(attrs.strikethrough, isNull);
      expect(attrs.inlineCode, isNull);
      expect(attrs.link, isNull);
      expect(attrs.color, isNull);
      expect(attrs.backgroundColor, isNull);
    });

    test('isEmpty is true when all fields are null', () {
      expect(const InlineAttributes().isEmpty, isTrue);
    });

    test('isEmpty is false when any field is set', () {
      expect(const InlineAttributes(bold: true).isEmpty, isFalse);
      expect(
        const InlineAttributes(link: 'https://example.com').isEmpty,
        isFalse,
      );
    });

    group('toJson / fromJson round-trip', () {
      test('empty attributes produce empty map', () {
        expect(const InlineAttributes().toJson(), isEmpty);
      });

      test('set fields appear in json', () {
        const attrs = InlineAttributes(
          bold: true,
          italic: false,
          color: '#FF0000',
        );
        final json = attrs.toJson();
        expect(json['bold'], isTrue);
        expect(json['italic'], isFalse);
        expect(json['color'], '#FF0000');
        expect(json.containsKey('underline'), isFalse);
      });

      test('fromJson restores all fields', () {
        const original = InlineAttributes(
          bold: true,
          underline: true,
          link: 'https://dart.dev',
          backgroundColor: '#FFFF00',
        );
        expect(InlineAttributes.fromJson(original.toJson()), equals(original));
      });

      test('fromJson ignores unknown keys', () {
        final json = {'bold': true, 'unknownKey': 'ignored'};
        expect(InlineAttributes.fromJson(json).bold, isTrue);
      });
    });

    group('copyWith', () {
      test('returns same values when nothing overridden', () {
        const attrs = InlineAttributes(bold: true, color: '#000');
        expect(attrs.copyWith(), equals(attrs));
      });

      test('overrides specified fields', () {
        const attrs = InlineAttributes(bold: true, italic: false);
        final copy = attrs.copyWith(italic: true, underline: true);
        expect(copy.bold, isTrue);
        expect(copy.italic, isTrue);
        expect(copy.underline, isTrue);
      });
    });

    group('equality', () {
      test('structurally equal instances are equal', () {
        const a = InlineAttributes(bold: true, color: '#FFF');
        const b = InlineAttributes(bold: true, color: '#FFF');
        expect(a, equals(b));
      });

      test('different instances are not equal', () {
        expect(
          const InlineAttributes(bold: true),
          isNot(equals(const InlineAttributes(bold: false))),
        );
      });

      test('hash codes match for equal instances', () {
        const a = InlineAttributes(bold: true, italic: true);
        const b = InlineAttributes(bold: true, italic: true);
        expect(a.hashCode, equals(b.hashCode));
      });
    });
  });
}
