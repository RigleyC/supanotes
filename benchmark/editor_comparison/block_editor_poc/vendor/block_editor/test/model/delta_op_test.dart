import 'package:block_editor/block_editor.dart';
import 'package:test/test.dart';

void main() {
  group('TextOp', () {
    test('default attributes are empty InlineAttributes', () {
      expect(
        const TextOp('hello').attributes,
        equals(const InlineAttributes()),
      );
    });

    group('toJson / fromJson round-trip', () {
      test('plain text op omits attributes key', () {
        final json = const TextOp('hello').toJson();
        expect(json['type'], 'text');
        expect(json['text'], 'hello');
        expect(json.containsKey('attributes'), isFalse);
      });

      test('formatted op includes attributes', () {
        final json = const TextOp(
          'world',
          attributes: InlineAttributes(bold: true),
        ).toJson();
        final attributes = json['attributes'] as Map<String, dynamic>;
        expect(attributes['bold'], isTrue);
      });

      test('fromJson restores plain op', () {
        final op = const TextOp('hello');
        expect(DeltaOp.fromJson(op.toJson()), equals(op));
      });

      test('fromJson restores formatted op', () {
        final op = const TextOp(
          'styled',
          attributes: InlineAttributes(italic: true, color: '#123'),
        );
        expect(DeltaOp.fromJson(op.toJson()), equals(op));
      });
    });

    test('fromJson throws FormatException for unknown type', () {
      expect(
        () => DeltaOp.fromJson({'type': 'embed', 'data': <String, dynamic>{}}),
        throwsFormatException,
      );
    });

    group('copyWith', () {
      test('overrides text', () {
        expect(const TextOp('old').copyWith(text: 'new').text, 'new');
      });

      test('preserves attributes when not overridden', () {
        final op = const TextOp(
          'hello',
          attributes: InlineAttributes(bold: true),
        );
        expect(op.copyWith(text: 'world').attributes.bold, isTrue);
      });
    });

    group('equality', () {
      test('equal ops', () {
        final a = const TextOp(
          'hello',
          attributes: InlineAttributes(bold: true),
        );
        final b = const TextOp(
          'hello',
          attributes: InlineAttributes(bold: true),
        );
        expect(a, equals(b));
      });

      test('different text', () {
        expect(const TextOp('a'), isNot(equals(const TextOp('b'))));
      });

      test('different attributes', () {
        expect(
          const TextOp('a', attributes: InlineAttributes(bold: true)),
          isNot(equals(const TextOp('a'))),
        );
      });
    });
  });
}
