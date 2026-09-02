import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_remote_sync_coordinator.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';

void main() {
  test('device B converges after device A publishes a remote note change', () async {
    final deviceA = AppDatabase.test();
    final deviceB = AppDatabase.test();
    addTearDown(deviceA.close);
    addTearDown(deviceB.close);
    final server = _FakeRemoteServer();

    await _writeLocalSnapshot(
      deviceA,
      revision: server.revision,
      document: server.document,
    );

    final storeB = SyncInboxStore(deviceB);
    var pollCount = 0;
    var coordinatorB = _buildCoordinator(
      database: deviceB,
      store: storeB,
      server: server,
      onPoll: () => pollCount++,
    );
    await coordinatorB.syncOnce();

    final initialB = await deviceB.noteOperationsDao
        .watchNoteDocument('shared-note')
        .first;
    expect(initialB!.revision, 1);
    expect(initialB.materializedDocumentJson, contains('before'));

    server.publishEditFromDeviceA('after from device A');
    await _writeLocalSnapshot(
      deviceA,
      revision: server.revision,
      document: server.document,
    );

    await coordinatorB.syncOnce();

    final convergedB = await deviceB.noteOperationsDao
        .watchNoteDocument('shared-note')
        .first;
    expect(convergedB!.revision, 2);
    expect(convergedB.materializedDocumentJson, contains('after from device A'));
    expect(await storeB.getCursor('user-1'), 1);
    expect(pollCount, 1);

    // Recreate the device-B sync process. The durable cursor prevents the
    // already-applied change from being replayed after an app restart.
    await coordinatorB.dispose();
    coordinatorB = _buildCoordinator(
      database: deviceB,
      store: SyncInboxStore(deviceB),
      server: server,
      onPoll: () => pollCount++,
    );
    await coordinatorB.syncOnce();
    await coordinatorB.dispose();

    expect(pollCount, 1);
    expect(await SyncInboxStore(deviceB).getCursor('user-1'), 1);
  });
}

NoteRemoteSyncCoordinator _buildCoordinator({
  required AppDatabase database,
  required SyncInboxStore store,
  required _FakeRemoteServer server,
  required void Function() onPoll,
}) {
  return NoteRemoteSyncCoordinator(
    userId: 'user-1',
    store: store,
    fetchChanges: server.fetchChanges,
    bootstrapCatalog: () => _writeLocalSnapshot(
      database,
      revision: server.revision,
      document: server.document,
    ),
    isNoteActive: (_) => false,
    syncPending: (_) async {},
    confirmedRevision: (_) async =>
        (await database.noteOperationsDao
                .watchNoteDocument('shared-note')
                .first)
            ?.revision,
    pollAndReconcile: (_) async {
      onPoll();
      await _writeLocalSnapshot(
        database,
        revision: server.revision,
        document: server.document,
      );
    },
    hydrateRemote: (_) async {},
    deleteLocal: database.deleteNoteData,
  );
}

Future<void> _writeLocalSnapshot(
  AppDatabase database, {
  required int revision,
  required Map<String, dynamic> document,
}) async {
  final existing = await database.notesDao.getNoteById('shared-note');
  if (existing == null) {
    await database.notesDao.createNote(
      NotesCompanion.insert(
        id: 'shared-note',
        userId: 'user-1',
        content: '',
        createdAt: DateTime.utc(2026, 9, 2),
        updatedAt: DateTime.utc(2026, 9, 2),
        hasRemoteCopy: const Value(true),
      ),
    );
  }
  final encoded = jsonEncode(document);
  await database.noteOperationsDao.upsertNoteDocument(
    LocalNoteDocumentsCompanion.insert(
      noteId: 'shared-note',
      revision: revision,
      documentJson: encoded,
      updatedAt: DateTime.utc(2026, 9, 2, 12, revision),
      materializedDocumentJson: Value(encoded),
      materializedUpdatedAt: Value(
        DateTime.utc(2026, 9, 2, 12, revision),
      ),
    ),
  );
}

final class _FakeRemoteServer {
  int revision = 1;
  int _sequence = 0;
  Map<String, dynamic> document = _document('before');
  final List<SyncChange> _changes = [];

  void publishEditFromDeviceA(String text) {
    revision++;
    document = _document(text);
    _sequence++;
    _changes.add(
      SyncChange(
        sequence: _sequence,
        type: 'note_changed',
        noteId: 'shared-note',
        revision: revision,
        createdAt: DateTime.utc(2026, 9, 2, 12, revision),
      ),
    );
  }

  Future<SyncChangePage> fetchChanges({
    required int after,
    required int limit,
  }) async {
    final pending = _changes
        .where((change) => change.sequence > after)
        .take(limit)
        .toList(growable: false);
    final cursor = pending.isEmpty ? after : pending.last.sequence;
    final hasMore = _changes.any((change) => change.sequence > cursor);
    return SyncChangePage(
      cursor: cursor,
      watermark: _sequence,
      hasMore: hasMore,
      changes: pending,
    );
  }
}

Map<String, dynamic> _document(String text) => {
  'schemaVersion': 1,
  'blocks': [
    {
      'id': 'title',
      'type': 'paragraph',
      'delta': [
        {'insert': text},
      ],
    },
  ],
};
