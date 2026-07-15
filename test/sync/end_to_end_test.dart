import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

void main() {
  test('local mutation persists and survives reload', () async {
    final db = AppDatabase.test(executor: NativeDatabase.memory());
    await db.into(db.notes).insert(NotesCompanion.insert(
          id: 'n-1',
          userId: 'u-1',
          content: '',
          createdAt: DateTime.utc(2025, 1, 1),
          updatedAt: DateTime.utc(2025, 1, 1),
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ));

    final mgr = YjsSyncManager(db: db, userId: 'u-1');
    final doc = await mgr.loadDoc('n-1');
    doc.transact((txn) {
      doc.getMap<Object>('nodes')!.set(
          'node-x',
          '{"id":"node-x","position":0,"type":"paragraph",'
              '"data":{"text":"edit"}}');
      doc.getText('content/node-x')!.insert(0, 'edit');
    });
    await mgr.persist('n-1');

    final mgr2 = YjsSyncManager(db: db, userId: 'u-1');
    final restored = await mgr2.loadDoc('n-1');
    expect(restored.getMap<Object>('nodes')!.keys, contains('node-x'));
    expect(restored.getText('content/node-x')!.toString(), 'edit');
    await db.close();
  });
}
