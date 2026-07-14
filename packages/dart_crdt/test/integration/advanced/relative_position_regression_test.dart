import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/advanced_regression_helpers.dart';

void main() {
  group('advanced relative position regressions', () {
    test('follows redo items after undo and preserves no-follow behavior', () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final manager = UndoManager(doc);
      applyAdvancedUpdate(
        doc,
        advancedTextDoc(1, 'abc', root: 'body'),
      );
      final text = doc.get('body', SharedTypeKind.text);
      final position = createRelativePositionFromTypeIndex(text, 1);

      expect(_absoluteIndex(position, doc), 1);

      manager.undo();
      expect(advancedRootText(doc, root: 'body'), isEmpty);
      expect(_absoluteIndex(position, doc), 0);

      manager.redo();
      expect(advancedRootText(doc, root: 'body'), 'abc');
      expect(_absoluteIndex(position, doc), 1);
      expect(
        createAbsolutePositionFromRelativePosition(
          position,
          doc,
          followRedoneItems: false,
        )?.index,
        0,
      );
    });

    test('resolves equivalent indexes in remote clones', () {
      final source = advancedDocWithContent(
        2,
        [ContentString('ab'), ContentString('cd')],
        root: 'body',
      );
      final first = Doc(gc: false)..get('body', SharedTypeKind.text);
      final clone = Doc(gc: false)..get('body', SharedTypeKind.text);
      applyAdvancedUpdate(first, source);
      applyAdvancedUpdate(clone, source);

      final type = first.get('body', SharedTypeKind.text);
      final left = createRelativePositionFromTypeIndex(type, 2, assoc: -1);
      final right = createRelativePositionFromTypeIndex(type, 2);

      expect(_absoluteIndex(left, first), 2);
      expect(_absoluteIndex(left, clone), 2);
      expect(_absoluteIndex(right, first), 2);
      expect(_absoluteIndex(right, clone), 2);
      expect(compareRelativePositions(left, right), isFalse);
    });
  });
}

int? _absoluteIndex(RelativePosition position, Doc doc) {
  return createAbsolutePositionFromRelativePosition(position, doc)?.index;
}
