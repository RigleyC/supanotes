import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:dart_crdt/src/sync/state_vector.dart';
import 'package:test/test.dart';

void main() {
  group('out-of-order update delivery', () {
    test('two causally-incomplete updates both integrate once deps arrive', () {
      // Source produces three causally-dependent updates U1 -> U2 -> U3.
      final source = Doc();
      final text = source.getText('body');

      final sv0 = encodeDocumentStateVector(source);
      text.insertText(0, 'A');
      final u1 = encodeStateAsUpdate(source, sv0);

      final sv1 = encodeDocumentStateVector(source);
      text.insertText(1, 'B');
      final u2 = encodeStateAsUpdate(source, sv1);

      final sv2 = encodeDocumentStateVector(source);
      text.insertText(2, 'C');
      final u3 = encodeStateAsUpdate(source, sv2);

      expect(source.getText('body').toPlainText(), 'ABC');

      // Target receives them out of order: U2, then U3 (each missing its
      // predecessor), then finally U1 which unblocks the chain.
      final target = Doc();
      applyUpdate(target, u2);
      applyUpdate(target, u3);
      applyUpdate(target, u1);

      // Both pending updates must survive and converge to the source.
      expect(target.getText('body').toPlainText(), 'ABC');
    });
  });
}
