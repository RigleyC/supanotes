import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/advanced_regression_helpers.dart';

void main() {
  group('advanced suggestion regressions', () {
    test('syncs base document updates to suggestion document until destroyed',
        () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false);
      final manager = createAttributionManagerFromDiff(previous, next);

      applyAdvancedUpdate(previous, advancedTextDoc(1, 'base'));
      expect(advancedRootText(next), 'base');

      manager.destroy();
      applyAdvancedUpdate(previous, advancedTextDoc(2, ' only'));

      expect(advancedRootText(previous), contains('only'));
      expect(advancedRootText(next), isNot(contains('only')));
    });

    test('accepts and rejects inclusive selected suggestion ranges', () {
      final previous = Doc(gc: false);
      final next = Doc(gc: false, clientId: ClientId(9));
      applyAdvancedUpdate(next, advancedTextDoc(3, 'abcd'));
      final manager = createAttributionManagerFromDiff(previous, next);

      manager.acceptChanges(advancedId(3, 1), advancedId(3, 2));
      manager.rejectChanges(advancedId(3, 0), advancedId(3, 0));

      expect(advancedRootText(previous), 'bc');
      expect(advancedRootText(next), 'bcd');
      expect(manager.suggestedChanges.inserts.hasId(advancedId(3, 0)), isFalse);
      expect(manager.suggestedChanges.inserts.hasId(advancedId(3, 3)), isTrue);
    });
  });
}
