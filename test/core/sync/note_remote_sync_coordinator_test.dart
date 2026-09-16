import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_remote_sync_coordinator.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/sync_inbox_store.dart';

void main() {
  test(
    'bootstrap snapshots catalog at watermark then catches concurrent changes',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final store = SyncInboxStore(db);
      final fetchAfter = <int>[];
      final scopes = <SyncFeedScope>[];
      final bootstrapPhases = <String>[];
      var catalogPulls = 0;
      var newChangeExists = false;

      final coordinator = NoteRemoteSyncCoordinator(
        userId: 'user-1',
        store: store,
        fetchChanges:
            ({
              required after,
              required limit,
              scope = SyncFeedScope.notes,
            }) async {
              fetchAfter.add(after);
              scopes.add(scope);
              if (after == 0) {
                return const SyncChangePage(
                  cursor: 1,
                  watermark: 12,
                  hasMore: false,
                  changes: [],
                );
              }
              if (after == 12 && newChangeExists) {
                return SyncChangePage(
                  cursor: 13,
                  watermark: 13,
                  hasMore: false,
                  changes: [
                    SyncChange(
                      sequence: 13,
                      type: 'note_preferences_changed',
                      noteId: 'n1',
                      createdAt: DateTime.utc(2026, 9, 2),
                    ),
                  ],
                );
              }
              return SyncChangePage(
                cursor: after,
                watermark: after,
                hasMore: false,
                changes: const [],
              );
            },
        fetchBootstrap: () async {
          bootstrapPhases.add('fetch');
          catalogPulls++;
          return NoteRemoteSyncBootstrap(
            applyNotesInTransaction: () async {
              bootstrapPhases.add('apply');
              newChangeExists = true;
            },
            applyTasksInTransaction: () async {},
          );
        },
        noteApplier: _noteApplier(
          syncPending: (_) async {},
          confirmedRevision: (_) async => 0,
          pollAndReconcile: (_) async {},
          hydrateRemote: (_) async {},
          deleteLocal: (_) async {},
        ),
        taskApplier: const DisabledNoteRemoteSyncTaskApplier(),
      );

      await coordinator.syncOnce();
      await coordinator.syncOnce();

      expect(catalogPulls, 1);
      expect(bootstrapPhases, ['fetch', 'apply']);
      expect(scopes, [
        SyncFeedScope.notes,
        SyncFeedScope.notes,
        SyncFeedScope.notes,
      ]);
      expect(fetchAfter.take(2), [0, 12]);
      final appliedRows = await (db.select(db.syncInbox)).get();
      expect(appliedRows.single.appliedAt, isNotNull);
      expect(await store.isBootstrapComplete('user-1'), isTrue);
      expect(await store.getCursor('user-1'), 13);
    },
  );

  test(
    'note change drains local outbox before polling and hydration',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final store = SyncInboxStore(db);
      await store.completeBootstrap(userId: 'user-1', cursor: 0);
      final calls = <String>[];

      final coordinator = NoteRemoteSyncCoordinator(
        userId: 'user-1',
        store: store,
        fetchChanges:
            ({
              required after,
              required limit,
              scope = SyncFeedScope.notes,
            }) async => SyncChangePage(
              cursor: 4,
              watermark: 4,
              hasMore: false,
              changes: [
                SyncChange(
                  sequence: 4,
                  type: 'note_changed',
                  noteId: 'n1',
                  revision: 8,
                  createdAt: DateTime.utc(2026, 9, 2),
                ),
              ],
            ),
        fetchBootstrap: () async => NoteRemoteSyncBootstrap(
          applyNotesInTransaction: () async {},
          applyTasksInTransaction: () async {},
        ),
        noteApplier: _noteApplier(
          syncPending: (id) async => calls.add('outbox:$id'),
          confirmedRevision: (_) async => 6,
          pollAndReconcile: (id) async => calls.add('poll:$id'),
          hydrateRemote: (id) async => calls.add('hydrate:$id'),
          deleteLocal: (_) async {},
        ),
        taskApplier: const DisabledNoteRemoteSyncTaskApplier(),
      );

      await coordinator.syncOnce();

      expect(calls, ['outbox:n1', 'poll:n1', 'hydrate:n1']);
    },
  );

  test('deleted and revoked notes are removed without hydration', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final store = SyncInboxStore(db);
    await store.completeBootstrap(userId: 'user-1', cursor: 0);
    final deleted = <String>[];
    var hydrated = 0;

    final coordinator = NoteRemoteSyncCoordinator(
      userId: 'user-1',
      store: store,
      fetchChanges:
          ({
            required after,
            required limit,
            scope = SyncFeedScope.notes,
          }) async => SyncChangePage(
            cursor: 2,
            watermark: 2,
            hasMore: false,
            changes: [
              SyncChange(
                sequence: 1,
                type: 'note_deleted',
                noteId: 'n1',
                createdAt: DateTime.utc(2026, 9, 2),
              ),
              SyncChange(
                sequence: 2,
                type: 'note_access_revoked',
                noteId: 'n2',
                createdAt: DateTime.utc(2026, 9, 2),
              ),
            ],
          ),
      fetchBootstrap: () async => NoteRemoteSyncBootstrap(
        applyNotesInTransaction: () async {},
        applyTasksInTransaction: () async {},
      ),
      noteApplier: _noteApplier(
        syncPending: (_) async {},
        confirmedRevision: (_) async => null,
        pollAndReconcile: (_) async {},
        hydrateRemote: (_) async => hydrated++,
        deleteLocal: (id) async => deleted.add(id),
      ),
      taskApplier: const DisabledNoteRemoteSyncTaskApplier(),
    );

    await coordinator.syncOnce();

    expect(deleted, ['n1', 'n2']);
    expect(hydrated, 0);
  });

  test(
    'task bootstrap uses all watermark and ignores marker changes',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final store = SyncInboxStore(db);
      final scopes = <SyncFeedScope>[];
      final applied = <String>[];
      var bootstrappedTasks = 0;

      final coordinator = NoteRemoteSyncCoordinator(
        userId: 'user-1',
        store: store,
        fetchChanges:
            ({
              required after,
              required limit,
              scope = SyncFeedScope.notes,
            }) async {
              scopes.add(scope);
              if (after == 0) {
                return SyncChangePage(
                  cursor: 4,
                  watermark: 9,
                  hasMore: false,
                  changes: [
                    SyncChange(
                      sequence: 4,
                      type: 'task_changed',
                      taskId: 'marker-task',
                      createdAt: DateTime.utc(2026, 9, 2),
                    ),
                  ],
                );
              }
              if (after == 9) {
                return SyncChangePage(
                  cursor: 11,
                  watermark: 11,
                  hasMore: false,
                  changes: [
                    SyncChange(
                      sequence: 10,
                      type: 'task_changed',
                      taskId: 'task-1',
                      createdAt: DateTime.utc(2026, 9, 2),
                    ),
                    SyncChange(
                      sequence: 11,
                      type: 'task_deleted',
                      taskId: 'task-2',
                      createdAt: DateTime.utc(2026, 9, 2),
                    ),
                  ],
                );
              }
              return SyncChangePage(
                cursor: after,
                watermark: after,
                hasMore: false,
                changes: const [],
              );
            },
        fetchBootstrap: () async => NoteRemoteSyncBootstrap(
          applyNotesInTransaction: () async {},
          applyTasksInTransaction: () async => bootstrappedTasks++,
        ),
        noteApplier: _noteApplier(
          syncPending: (_) async {},
          confirmedRevision: (_) async => null,
          pollAndReconcile: (_) async {},
          hydrateRemote: (_) async {},
          deleteLocal: (_) async {},
        ),
        taskApplier: NoteRemoteSyncTaskCallbacks(
          applyChanged: (id) async => applied.add('changed:$id'),
          applyDeleted: (id) async => applied.add('deleted:$id'),
        ),
      );

      await coordinator.syncOnce();

      expect(bootstrappedTasks, 1);
      expect(scopes, [SyncFeedScope.all, SyncFeedScope.all]);
      expect(applied, ['changed:task-1', 'deleted:task-2']);
      expect(await store.getBootstrapVersion('user-1'), 2);
      expect(await store.getCursor('user-1'), 11);
    },
  );

  test(
    'retries a failed task bootstrap without committing version two',
    () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final store = SyncInboxStore(db);
      var taskAttempts = 0;
      final scopes = <SyncFeedScope>[];

      final coordinator = NoteRemoteSyncCoordinator(
        userId: 'user-1',
        store: store,
        fetchChanges:
            ({
              required after,
              required limit,
              scope = SyncFeedScope.notes,
            }) async {
              scopes.add(scope);
              if (scope == SyncFeedScope.notes) {
                return const SyncChangePage(
                  cursor: 2,
                  watermark: 2,
                  hasMore: false,
                  changes: [],
                );
              }
              return SyncChangePage(
                cursor: after,
                watermark: after,
                hasMore: false,
                changes: const [],
              );
            },
        fetchBootstrap: () async => NoteRemoteSyncBootstrap(
          applyNotesInTransaction: () async {},
          applyTasksInTransaction: () async {
            taskAttempts++;
            if (taskAttempts == 1) throw StateError('offline');
          },
        ),
        noteApplier: _noteApplier(
          syncPending: (_) async {},
          confirmedRevision: (_) async => null,
          pollAndReconcile: (_) async {},
          hydrateRemote: (_) async {},
          deleteLocal: (_) async {},
        ),
        taskApplier: NoteRemoteSyncTaskCallbacks(
          applyChanged: (id) async {},
          applyDeleted: (id) async {},
        ),
      );

      await expectLater(coordinator.syncOnce(), throwsStateError);
      expect(await store.getBootstrapVersion('user-1'), 0);
      expect(await store.isBootstrapComplete('user-1'), isFalse);

      await coordinator.syncOnce();
      expect(taskAttempts, 2);
      expect(await store.getBootstrapVersion('user-1'), 2);
      expect(scopes, [
        SyncFeedScope.all,
        SyncFeedScope.all,
        SyncFeedScope.all,
      ]);
    },
  );
}

NoteRemoteSyncNoteApplier _noteApplier({
  required Future<void> Function(String) syncPending,
  required Future<int?> Function(String) confirmedRevision,
  required Future<void> Function(String) pollAndReconcile,
  required Future<void> Function(String) hydrateRemote,
  required Future<void> Function(String) deleteLocal,
}) {
  return NoteRemoteSyncNoteApplier(
    isActive: (_) => false,
    syncPending: syncPending,
    confirmedRevision: confirmedRevision,
    pollAndReconcile: pollAndReconcile,
    hydrateRemote: hydrateRemote,
    deleteLocal: deleteLocal,
  );
}
