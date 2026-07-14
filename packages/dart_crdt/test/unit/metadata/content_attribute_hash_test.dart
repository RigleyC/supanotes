import 'package:dart_crdt/src/metadata/content_attribute.dart';
import 'package:test/test.dart';

void main() {
  group('ContentAttribute.stableHash (web-safe FNV digest)', () {
    test('produces a 16-character lowercase hex digest', () {
      final hash = ContentAttribute('bold', true).stableHash;

      expect(hash, hasLength(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hash), isTrue);
    });

    test('is deterministic for equal attributes', () {
      expect(
        ContentAttribute('color', 'red').stableHash,
        ContentAttribute('color', 'red').stableHash,
      );
    });

    test('differs across distinct attributes', () {
      final hashes = <String>{
        for (var i = 0; i < 1000; i += 1)
          ContentAttribute('attr$i', 'value$i').stableHash,
      };

      // No collisions across a large, varied set of inputs.
      expect(hashes, hasLength(1000));
    });

    test('only depends on name and value, not identity', () {
      const name = 'a-fairly-long-attribute-name-to-exercise-byte-mixing';
      expect(
        ContentAttribute(name, 'payload-value').stableHash,
        ContentAttribute(name, 'payload-value').stableHash,
      );
    });

    test('high bytes that would overflow 32 bits stay exact', () {
      // Long inputs drive the lane accumulators through their full range,
      // which is where naive 64-bit / unmasked-multiply implementations
      // diverge on the web. The digest must still be well-formed.
      final hash = ContentAttribute('k', 'z' * 4096).stableHash;

      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hash), isTrue);
    });
  });
}
