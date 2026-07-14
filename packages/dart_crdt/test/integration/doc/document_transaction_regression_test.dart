import 'package:dart_crdt/src/content/content.dart';
import 'package:dart_crdt/src/doc/doc.dart';
import 'package:dart_crdt/src/structs/id.dart';
import 'package:dart_crdt/src/sync/apply_update.dart';
import 'package:dart_crdt/src/sync/state_update.dart';
import 'package:test/test.dart';

import '../../helpers/doc_regression_helpers.dart';

void main() {
  group('document transaction regressions', () {
    test('keeps recursive transactions in one cleanup group', () {
      final doc = Doc();
      final root = doc.get();
      final calls = <String>[];
      late final Transaction outer;
      late final Transaction nested;
      late final Transaction cleanupNested;

      doc
        ..beforeAllTransactions.add((_) => calls.add('beforeAll'))
        ..beforeTransaction.add((_) => calls.add('beforeTransaction'))
        ..afterTransactionCleanup.add((transaction) {
          calls.add('afterCleanup:${transaction.done}');
        })
        ..afterAllTransactions.add((_) => calls.add('afterAll'));

      doc.transact((transaction) {
        outer = transaction;
        root.setAttr('title', 'outer');
        doc.transact((transaction) {
          nested = transaction;
          root.setAttr('subtitle', 'nested');
          transaction.addCleanupCallback((cleaned) {
            doc.transact((transaction) {
              cleanupNested = transaction;
              root.setAttr('cleanup', cleaned.done);
            });
          });
        });
      });

      expect(nested, same(outer));
      expect(cleanupNested, same(outer));
      expect(root.getAttrs(), {
        'title': 'outer',
        'subtitle': 'nested',
        'cleanup': false,
      });
      expect(calls, [
        'beforeAll',
        'beforeTransaction',
        'afterCleanup:true',
        'afterAll',
      ]);
      expect(doc.currentTransaction, isNull);
      expect(doc.pendingTransactionCleanup, isEmpty);
    });

    test('keeps same-named roots isolated across documents', () {
      final left = Doc();
      final right = Doc();
      final leftRoot = left.get('items');
      final rightRoot = right.get('items');
      final child = SharedType(kind: SharedTypeKind.text, name: 'body');

      leftRoot
        ..setAttr('owner', 'left')
        ..setAttr('body', child);
      rightRoot.setAttr('owner', 'right');

      expect(leftRoot, isNot(same(rightRoot)));
      expect(child.doc, same(left));
      expect(rightRoot.getAttr('owner'), 'right');
      expect(
        () => rightRoot.setAttr('body', child),
        throwsA(isA<StateError>()),
      );
      expect(rightRoot.children, isNot(contains('body')));
    });

    test('replaces a duplicate local client id after remote insertion', () {
      final source = docWithStringItem(client: 7, parent: 'body', text: 'r');
      final target = Doc(gc: false, clientId: ClientId(7));
      final originalClient = target.clientId;

      applyUpdate(target, encodeStateAsUpdate(source), origin: 'remote');

      expect(target.clientId, isNot(originalClient));
      expect(target.store.getClock(originalClient), Clock(1));
      expect(
        target.itemParentForKey('body').items().single.content.content,
        ['r'],
      );

      final replacedClient = target.clientId;
      applyUpdate(target, encodeStateAsUpdate(source), origin: 'duplicate');

      expect(target.clientId, replacedClient);
      expect(target.store.getClock(originalClient), Clock(1));
    });
  });
}
