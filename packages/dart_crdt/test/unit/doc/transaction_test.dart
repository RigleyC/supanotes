import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/metadata/id_range.dart';
import 'package:dart_crdt/src/structs/abstract_struct.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:test/test.dart' hide Skip;

void main() {
  group('Doc transactions', () {
    test('captures before and after state around root transactions', () {
      final doc = Doc();
      late final Transaction transaction;
      final cleanupCalls = <String>[];

      final result = doc.transact(
        (current) {
          transaction = current;
          expect(current.beforeState, isEmpty);
          expect(current.afterState, isEmpty);
          expect(current.done, isFalse);
          expect(doc.currentTransaction, same(current));
          expect(doc.pendingTransactionCleanup, [current]);

          GC(id: _id(1, 0), length: 3).integrate(doc.store);
          current.addCleanupCallback((cleaned) {
            cleanupCalls.add('cleanup:${cleaned.done}');
          });
          return 42;
        },
        origin: 'unit',
      );

      expect(result, 42);
      expect(transaction.origin, 'unit');
      expect(transaction.local, isTrue);
      expect(transaction.done, isTrue);
      expect(transaction.afterState, {ClientId(1): Clock(3)});
      expect(cleanupCalls, ['cleanup:false']);
      expect(doc.currentTransaction, isNull);
      expect(doc.pendingTransactionCleanup, isEmpty);
    });

    test('reuses the outer transaction for nested and recursive calls', () {
      final doc = Doc();
      final calls = <String>[];
      late final Transaction outer;
      late final Transaction inner;
      late final Transaction recursive;

      doc.transact(
        (transaction) {
          outer = transaction;
          calls.add('outer');
          doc.transact(
            (transaction) {
              inner = transaction;
              calls.add('inner');
              doc.transact(
                (transaction) {
                  recursive = transaction;
                  calls.add('recursive');
                },
                origin: 'recursive',
              );
            },
            origin: 'inner',
          );
        },
        origin: 'outer',
        local: false,
      );

      expect(calls, ['outer', 'inner', 'recursive']);
      expect(inner, same(outer));
      expect(recursive, same(outer));
      expect(outer.origin, 'outer');
      expect(outer.local, isFalse);
      expect(outer.done, isTrue);
    });

    test('collects changed maps, metadata, ranges, and subdocuments', () {
      final doc = Doc();
      final sharedType = doc.get('items', SharedTypeKind.array);
      final subdocument = Subdocument(guid: 'child');
      late final Transaction transaction;

      doc.transact((current) {
        transaction = current
          ..markChanged(sharedType, 0)
          ..markChanged(sharedType, 'title')
          ..markParentChanged(sharedType, 'event-1')
          ..addCleanupTarget(sharedType)
          ..addInsertedRange(ClientId(1), _range(0, 2))
          ..addDeletedRange(ClientId(1), _range(2, 1))
          ..queueMerge(GC(id: _id(1, 0), length: 1))
          ..setMeta('originName', 'test')
          ..setMeta('nullable', null)
          ..addSubdocument(subdocument)
          ..loadSubdocument(subdocument)
          ..removeSubdocument(subdocument);
        current.shouldCleanupFormatting = true;
      });

      expect(transaction.changed[sharedType], {0, 'title'});
      expect(transaction.changedParentTypes[sharedType], ['event-1']);
      expect(transaction.cleanupSet, {sharedType});
      expect(
        transaction.insertSet.has(client: ClientId(1), clock: Clock(1)),
        isTrue,
      );
      expect(
        transaction.deleteSet.has(client: ClientId(1), clock: Clock(2)),
        isTrue,
      );
      expect(transaction.mergeStructs, hasLength(1));
      expect(transaction.getMeta('originName'), 'test');
      expect(transaction.hasMeta('nullable'), isTrue);
      expect(transaction.deleteMeta('nullable'), isTrue);
      expect(transaction.subdocsAdded, {subdocument});
      expect(transaction.subdocsLoaded, {subdocument});
      expect(transaction.subdocsRemoved, {subdocument});
      expect(transaction.shouldCleanupFormatting, isTrue);
      expect(() => transaction.changed.clear(), throwsUnsupportedError);
      expect(() => transaction.metadata.clear(), throwsUnsupportedError);
    });

    test('runs cleanup when the transaction callback throws', () {
      final doc = Doc();
      late final Transaction transaction;
      var cleanupRan = false;

      expect(
        () => doc.transact((current) {
          transaction = current;
          current.addCleanupCallback((cleaned) {
            cleanupRan = true;
            expect(cleaned.done, isFalse);
          });
          throw StateError('callback failed');
        }),
        throwsA(isA<StateError>()),
      );

      expect(cleanupRan, isTrue);
      expect(transaction.done, isTrue);
      expect(doc.currentTransaction, isNull);
      expect(doc.pendingTransactionCleanup, isEmpty);
    });

    test('marks transactions done when cleanup callbacks throw', () {
      final doc = Doc();
      late final Transaction transaction;

      expect(
        () => doc.transact((current) {
          transaction = current;
          current.addCleanupCallback((_) {
            throw StateError('cleanup failed');
          });
        }),
        throwsA(isA<StateError>()),
      );

      expect(transaction.done, isTrue);
      expect(doc.currentTransaction, isNull);
      expect(doc.pendingTransactionCleanup, isEmpty);
    });
  });
}

Id _id(int client, int clock) {
  return Id(client: ClientId(client), clock: Clock(clock));
}

IdRange _range(int start, int length) {
  return IdRange(start: Clock(start), length: length);
}
