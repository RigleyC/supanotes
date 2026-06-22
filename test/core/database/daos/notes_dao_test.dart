import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';

void main() {
  test('getInboxNote returns the current user inbox only', () async {
    final db = AppDatabase.test();
    final now = DateTime(2026, 6, 17);

    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'inbox-user-1',
            userId: 'user-1',
            content: 'User 1 inbox',
            isInbox: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'inbox-user-2',
            userId: 'user-2',
            content: 'User 2 inbox',
            isInbox: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final inbox = await db.notesDao.getInboxNote('user-1');

    expect(inbox, isNotNull);
    expect(inbox!.note.id, 'inbox-user-1');

    await db.close();
  });
}
