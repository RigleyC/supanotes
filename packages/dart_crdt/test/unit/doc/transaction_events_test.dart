import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/events/event_handler.dart';
import 'package:test/test.dart';

void main() {
  group('Transaction event ordering', () {
    test('emits document hooks around transaction cleanup in order', () {
      final doc = Doc();
      final calls = <String>[];

      _recordTransactionEvents(doc, calls);

      doc.transact((transaction) {
        calls.add('callback:${transaction.done}');
        transaction.addCleanupCallback((cleaned) {
          calls.add('cleanup:${cleaned.done}');
        });
      });

      expect(calls, [
        'beforeAll:true',
        'beforeTransaction:false',
        'callback:false',
        'beforeObserverCalls:false',
        'afterTransaction:false',
        'cleanup:false',
        'afterTransactionCleanup:true',
        'afterAll:false',
      ]);
    });

    test('keeps nested transactions inside the outer event group', () {
      final doc = Doc();
      final calls = <String>[];
      late final Transaction outer;
      late final Transaction nested;

      _recordTransactionEvents(doc, calls);

      doc.transact((transaction) {
        outer = transaction;
        calls.add('outer');
        doc.transact((transaction) {
          nested = transaction;
          calls.add('nested');
        });
        transaction.addCleanupCallback((cleaned) {
          doc.transact((transaction) {
            expect(transaction, same(cleaned));
            calls.add('cleanupNested');
          });
        });
      });

      expect(nested, same(outer));
      expect(calls, [
        'beforeAll:true',
        'beforeTransaction:false',
        'outer',
        'nested',
        'beforeObserverCalls:false',
        'afterTransaction:false',
        'cleanupNested',
        'afterTransactionCleanup:true',
        'afterAll:false',
      ]);
    });

    test('handles listener mutation during dispatch', () {
      final doc = Doc();
      final calls = <String>[];
      var addedLateListener = false;
      late final EventSubscription second;

      doc.beforeTransaction.add((transaction) {
        calls.add('first');
        second.cancel();
        if (!addedLateListener) {
          addedLateListener = true;
          doc.beforeTransaction.add((_) => calls.add('late'));
        }
      });
      second = doc.beforeTransaction.add((_) => calls.add('second'));
      doc.beforeTransaction.add((_) => calls.add('third'));

      doc.transact((_) {});
      doc.transact((_) {});

      expect(calls, ['first', 'third', 'first', 'third', 'late']);
      expect(second.isActive, isFalse);
    });

    test('still emits cleanup hooks when event listeners throw', () {
      final doc = Doc();
      final calls = <String>[];

      doc.beforeObserverCalls
        ..add((_) {
          calls.add('beforeObserverThrows');
          throw StateError('observer failed');
        })
        ..add((_) => calls.add('beforeObserverContinues'));
      doc.afterTransaction.add((_) => calls.add('afterTransaction'));
      doc.afterTransactionCleanup.add((transaction) {
        calls.add('afterCleanup:${transaction.done}');
      });
      doc.afterAllTransactions.add((_) => calls.add('afterAll'));

      expect(
        () => doc.transact((transaction) {
          transaction.addCleanupCallback((_) => calls.add('cleanup'));
        }),
        throwsA(isA<EventDispatchException<Transaction>>()),
      );

      expect(calls, [
        'beforeObserverThrows',
        'beforeObserverContinues',
        'afterTransaction',
        'cleanup',
        'afterCleanup:true',
        'afterAll',
      ]);
      expect(doc.currentTransaction, isNull);
      expect(doc.pendingTransactionCleanup, isEmpty);
    });

    test('emits lifecycle hooks for no-update transactions', () {
      final doc = Doc();
      final calls = <String>[];

      _recordTransactionEvents(doc, calls);

      doc.transact((_) {});

      expect(doc.store.isEmpty, isTrue);
      expect(calls, [
        'beforeAll:true',
        'beforeTransaction:false',
        'beforeObserverCalls:false',
        'afterTransaction:false',
        'afterTransactionCleanup:true',
        'afterAll:false',
      ]);
    });
  });
}

void _recordTransactionEvents(Doc doc, List<String> calls) {
  doc
    ..beforeAllTransactions.add((document) {
      calls.add('beforeAll:${document.hasActiveTransaction}');
    })
    ..beforeTransaction.add((transaction) {
      calls.add('beforeTransaction:${transaction.done}');
    })
    ..beforeObserverCalls.add((transaction) {
      calls.add('beforeObserverCalls:${transaction.done}');
    })
    ..afterTransaction.add((transaction) {
      calls.add('afterTransaction:${transaction.done}');
    })
    ..afterTransactionCleanup.add((transaction) {
      calls.add('afterTransactionCleanup:${transaction.done}');
    })
    ..afterAllTransactions.add((document) {
      calls.add('afterAll:${document.hasActiveTransaction}');
    });
}
