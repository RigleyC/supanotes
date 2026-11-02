import 'package:block_editor/block_editor.dart';
import 'package:test/test.dart';

void main() {
  group('TextDelta', () {
    group('constructors', () {
      test('empty delta has no ops', () {
        expect(TextDelta.empty().ops, isEmpty);
      });

      test('fromPlainText wraps in a single TextOp', () {
        final delta = TextDelta.fromPlainText('hello');
        expect(delta.ops.length, 1);
        expect((delta.ops.first as TextOp).text, 'hello');
      });

      test('fromPlainText with empty string produces empty delta', () {
        expect(TextDelta.fromPlainText('').ops, isEmpty);
      });
    });

    group('plainText', () {
      test('concatenates all TextOp texts', () {
        final delta = TextDelta(const [
          TextOp('hello'),
          TextOp(' '),
          TextOp('world', attributes: InlineAttributes(bold: true)),
        ]);
        expect(delta.plainText, 'hello world');
      });
    });

    group('normalization', () {
      test('adjacent ops with same attributes are merged', () {
        final delta = TextDelta(const [TextOp('foo'), TextOp('bar')]);
        expect(delta.ops.length, 1);
        expect((delta.ops.first as TextOp).text, 'foobar');
      });

      test('adjacent ops with different attributes stay separate', () {
        final delta = TextDelta(const [
          TextOp('foo'),
          TextOp('bar', attributes: InlineAttributes(bold: true)),
        ]);
        expect(delta.ops.length, 2);
      });

      test('empty TextOps are removed', () {
        final delta = TextDelta(const [
          TextOp(''),
          TextOp('hello'),
          TextOp(''),
        ]);
        expect(delta.ops.length, 1);
        expect((delta.ops.first as TextOp).text, 'hello');
      });
    });

    group('append', () {
      test('merges ops with same attributes', () {
        final result = TextDelta.fromPlainText(
          'hello ',
        ).append(const TextOp('world'));
        expect(result.plainText, 'hello world');
        expect(result.ops.length, 1);
      });

      test('keeps separate for different attributes', () {
        final result = TextDelta.fromPlainText('hello').append(
          const TextOp(' world', attributes: InlineAttributes(bold: true)),
        );
        expect(result.ops.length, 2);
      });
    });

    group('concat', () {
      test('joins and normalizes', () {
        final result = TextDelta.fromPlainText(
          'hello ',
        ).concat(TextDelta.fromPlainText('world'));
        expect(result.plainText, 'hello world');
        expect(result.ops.length, 1);
      });
    });

    group('applyAttributes', () {
      test('applies bold to a sub-range', () {
        final result = TextDelta.fromPlainText(
          'hello world',
        ).applyAttributes(0, 5, const InlineAttributes(bold: true));
        expect((result.ops[0] as TextOp).text, 'hello');
        expect((result.ops[0] as TextOp).attributes.bold, isTrue);
        expect((result.ops[1] as TextOp).text, ' world');
        expect((result.ops[1] as TextOp).attributes.bold, isNull);
      });

      test('merges with existing attributes', () {
        final delta = TextDelta(const [
          TextOp('bold', attributes: InlineAttributes(bold: true)),
        ]);
        final result = delta.applyAttributes(
          0,
          4,
          const InlineAttributes(italic: true),
        );
        final op = result.ops.first as TextOp;
        expect(op.attributes.bold, isTrue);
        expect(op.attributes.italic, isTrue);
      });

      test('range outside content leaves delta unchanged', () {
        final delta = TextDelta.fromPlainText('short');
        expect(
          delta.applyAttributes(10, 15, const InlineAttributes(bold: true)),
          equals(delta),
        );
      });
    });

    group('slice', () {
      test('extracts middle portion', () {
        expect(
          TextDelta.fromPlainText('hello world').slice(6, 11).plainText,
          'world',
        );
      });

      test('preserves attributes in sliced ops', () {
        final delta = TextDelta(const [
          TextOp('hello', attributes: InlineAttributes(bold: true)),
          TextOp(' world'),
        ]);
        expect((delta.slice(0, 5).ops.first as TextOp).attributes.bold, isTrue);
      });
    });

    group('toJson / fromJson round-trip', () {
      test('empty delta', () {
        final original = TextDelta.empty();
        expect(TextDelta.fromJson(original.toJson()), equals(original));
      });

      test('complex mixed-format delta', () {
        final original = TextDelta(const [
          TextOp('plain'),
          TextOp(' bold', attributes: InlineAttributes(bold: true)),
          TextOp(
            ' link',
            attributes: InlineAttributes(link: 'https://dart.dev'),
          ),
        ]);
        expect(TextDelta.fromJson(original.toJson()), equals(original));
      });
    });

    group('equality', () {
      test('equal deltas', () {
        expect(
          TextDelta.fromPlainText('hello'),
          equals(TextDelta.fromPlainText('hello')),
        );
      });

      test('different plain text', () {
        expect(
          TextDelta.fromPlainText('hello'),
          isNot(equals(TextDelta.fromPlainText('world'))),
        );
      });
    });
  });
}
