import 'package:dart_crdt/dart_crdt.dart';
import 'package:test/test.dart';

void main() {
  group('UndoManager stack basics', () {
    test('captures doc transactions, metadata, defensive sets, and merges', () {
      final doc = Doc();
      final manager = UndoManager(doc);
      final added = <StackItemEvent>[];
      final updated = <StackItemEvent>[];
      manager.stackItemAdded.add(added.add);
      manager.stackItemUpdated.add(updated.add);

      applyUpdate(doc, encodeStateAsUpdate(_docWithItem(1, 'x')));
      manager.undoStack.single.meta['selection'] = 'cursor-a';
      manager.undoStack.single.inserts.add(_id(9, 0));
      doc.transact((transaction) => _delete(transaction, 1, 0));

      final item = manager.undoStack.single;
      expect(manager.undoStack, hasLength(1));
      expect(item.meta['selection'], 'cursor-a');
      expect(item.inserts.hasId(_id(1, 0)), isTrue);
      expect(item.inserts.hasId(_id(9, 0)), isFalse);
      expect(item.deletes.hasId(_id(1, 0)), isTrue);
      expect(added.single.stackItem, item);
      expect(updated.single.stackItem, item);
      expect(updated.single.type, StackItemEventType.undo);
    });

    test('honors stop capturing and zero capture timeout', () {
      final stopped = UndoManager(Doc());
      stopped.doc.transact((transaction) => _insert(transaction, 1, 0));
      stopped.stopCapturing();
      stopped.doc.transact((transaction) => _insert(transaction, 1, 1));

      final timedOut = UndoManager(Doc(), captureTimeout: Duration.zero);
      timedOut.doc.transact((transaction) => _insert(transaction, 2, 0));
      timedOut.doc.transact((transaction) => _insert(transaction, 2, 1));

      expect(stopped.undoStack, hasLength(2));
      expect(timedOut.undoStack, hasLength(2));
    });

    test('filters by shared type scope and supports scope extension', () {
      final doc = Doc();
      final first = doc.get('first');
      final second = doc.get('second');
      final manager = UndoManager(first);

      doc.transact((transaction) {
        second.markChanged('remote');
        _insert(transaction, 1, 0);
      });
      doc.transact((transaction) {
        first.markChanged('local');
        _insert(transaction, 1, 1);
      });
      manager
        ..stopCapturing()
        ..addToScope([second]);
      doc.transact((transaction) {
        second.markChanged('local');
        _insert(transaction, 1, 2);
      });

      expect(manager.scope, [first, second]);
      expect(manager.undoStack, hasLength(2));
    });

    test('honors origins, capture predicates, delete filters, and doc option',
        () {
      final doc = Doc();
      final manager = UndoManager(
        <Object>[],
        doc: doc,
        trackedOrigins: {'local'},
        captureTransaction: (transaction) => transaction.origin != 'blocked',
        deleteFilter: (_) => false,
      );

      doc.transact((transaction) => _insert(transaction, 1, 0));
      doc.transact(
        (transaction) => _insert(transaction, 1, 1),
        origin: 'local',
      );
      doc.transact(
        (transaction) => _insert(transaction, 1, 2),
        origin: 'blocked',
      );
      manager
        ..removeTrackedOrigin('local')
        ..addTrackedOrigin('remote');
      doc.transact(
        (transaction) => _insert(transaction, 1, 3),
        origin: 'local',
      );
      doc.transact(
        (transaction) => _insert(transaction, 1, 4),
        origin: 'remote',
      );

      expect(manager.undoStack, hasLength(1));
      expect(manager.undoStack.single.inserts.hasId(_id(1, 4)), isTrue);
      expect(manager.deleteFilter(_item(doc)), isFalse);
      expect(manager.doc, doc);
    });

    test('tracks undo/redo availability, clearing, and destroy lifecycle', () {
      final doc = Doc();
      final manager = UndoManager(doc);
      final popped = <StackItemEvent>[];
      final cleared = <StackClearedEvent>[];
      manager.stackItemPopped.add(popped.add);
      manager.stackCleared.add(cleared.add);
      applyUpdate(doc, encodeStateAsUpdate(_docWithItem(1, 'x')));

      final undoItem = manager.undo();
      expect(undoItem, isNotNull);
      expect(manager.canUndo(), isFalse);
      expect(manager.canRedo(), isTrue);
      expect(popped.single.type, StackItemEventType.undo);

      manager.redo();
      expect(manager.canUndo(), isTrue);
      expect(manager.canRedo(), isFalse);
      manager.undo();
      manager.clear(undoStack: false);

      expect(manager.canRedo(), isFalse);
      expect(cleared.single.undoStackCleared, isFalse);
      expect(cleared.single.redoStackCleared, isTrue);

      manager.destroy();
      doc.transact((transaction) => _insert(transaction, 2, 0));
      expect(manager.isDestroyed, isTrue);
      expect(manager.trackedOrigins.contains(manager), isFalse);
      expect(manager.undoStack, isEmpty);
    });
  });
}

void _insert(Transaction transaction, int client, int clock) {
  transaction.addInsertedRange(
    ClientId(client),
    IdRange(start: Clock(clock), length: 1),
  );
}

void _delete(Transaction transaction, int client, int clock) {
  transaction.addDeletedRange(
    ClientId(client),
    IdRange(start: Clock(clock), length: 1),
  );
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

Item _item(Doc doc) {
  return Item(
    id: _id(7, 0),
    parent: doc.itemParentForKey('root'),
    content: ContentString('x'),
  );
}

Doc _docWithItem(int client, String value) {
  final doc = Doc(gc: false, clientId: ClientId(client));
  doc.store.add(
    Item(
      id: _id(client, 0),
      parent: doc.itemParentForKey('root'),
      content: ContentString(value),
    ),
  );
  return doc;
}
