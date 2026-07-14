import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

import '../../helpers/advanced_regression_helpers.dart';

void main() {
  group('advanced undo/redo regressions', () {
    test('captures only dynamically tracked origins and emits pop events', () {
      final doc = Doc(gc: false, clientId: ClientId(9));
      final manager = UndoManager(doc, trackedOrigins: {'tracked'});
      final added = <StackItemEvent>[];
      final popped = <StackItemEvent>[];
      manager.stackItemAdded.add(added.add);
      manager.stackItemPopped.add(popped.add);

      applyAdvancedUpdate(doc, advancedTextDoc(1, 'a'), origin: 'ignored');
      manager.addTrackedOrigin('later');
      applyAdvancedUpdate(doc, advancedTextDoc(2, 'b'), origin: 'later');
      manager.removeTrackedOrigin('later');
      applyAdvancedUpdate(doc, advancedTextDoc(3, 'c'), origin: 'later');

      expect(manager.undoStack, hasLength(1));
      expect(added, hasLength(1));
      expect(advancedRootText(doc), contains('a'));
      expect(advancedRootText(doc), contains('b'));
      expect(advancedRootText(doc), contains('c'));

      final undone = manager.undo();

      expect(undone, isNotNull);
      expect(advancedRootText(doc), contains('a'));
      expect(advancedRootText(doc), isNot(contains('b')));
      expect(advancedRootText(doc), contains('c'));
      expect(popped.single.type, StackItemEventType.undo);

      final redone = manager.redo();

      expect(redone, isNotNull);
      expect(advancedRootText(doc), contains('b'));
      expect(popped.last.type, StackItemEventType.redo);
    });

    test('clears requested stacks without dropping the other stack', () {
      final doc = Doc(gc: false, clientId: ClientId(10));
      final manager = UndoManager(doc);
      final cleared = <StackClearedEvent>[];
      manager.stackCleared.add(cleared.add);
      applyAdvancedUpdate(doc, advancedTextDoc(4, 'x'));

      manager.undo();
      expect(manager.redoStack, hasLength(1));

      manager.clear(redoStack: false);
      expect(cleared, isEmpty);

      manager.clear(undoStack: false);
      expect(manager.redoStack, isEmpty);
      expect(cleared.single.undoStackCleared, isFalse);
      expect(cleared.single.redoStackCleared, isTrue);
    });
  });
}
