import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_sync_session.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';

class NoteCatalogSync {
  NoteCatalogSync({
    required NoteSyncClient syncClient,
    required AppDatabase database,
  }) : _syncClient = syncClient,
       _database = database,
       _taskProjectionEngine = TaskProjectionEngine(database: database);

  final NoteSyncClient _syncClient;
  final AppDatabase _database;
  final TaskProjectionEngine _taskProjectionEngine;

  Future<void> pullRemoteNotes(String userId) async {
    final rows = await _syncClient.listNotes();

    for (final raw in rows) {
      try {
        await _pullRemoteNote(
          userId: userId,
          json: raw,
        );
      } catch (error, stackTrace) {
        dev.log(
          '[NoteCatalogSync] Failed to hydrate ${raw['id']}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    dev.log('[NoteCatalogSync] Pulled ${rows.length} remote notes');
  }

  Future<void> _pullRemoteNote({
    required String userId,
    required Map<String, dynamic> json,
  }) async {
    final id = json['id'] as String;
    if (NoteSyncSession.isActive(id)) {
      dev.log('[NoteCatalogSync] Skipping active note $id');
      return;
    }
    final existing = await _database.notesDao.getNoteById(id);
    final localDocument = await (_database.select(
      _database.localNoteDocuments,
    )..where((document) => document.noteId.equals(id))).getSingleOrNull();
    final createdAt = DateTime.parse(json['created_at'] as String).toUtc();
    final updatedAt = DateTime.parse(json['updated_at'] as String).toUtc();

    if (existing != null &&
        (existing.isDirty ||
            (existing.hasRemoteCopy &&
                localDocument != null &&
                !updatedAt.isAfter(existing.updatedAt)))) {
      return;
    }

    if (existing == null) {
      await _database
          .into(_database.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              userId: userId,
              content: '',
              createdAt: createdAt,
              updatedAt: updatedAt,
              isDirty: const Value(false),
              hasRemoteCopy: const Value(false),
              collapseImages: Value(json['collapse_images'] as bool? ?? false),
            ),
          );
    }

    final remote = await _syncClient.getDocument(id);
    await _database.noteOperationsDao.upsertNoteDocument(
      LocalNoteDocumentsCompanion.insert(
        noteId: remote.noteId,
        revision: remote.revision,
        documentJson: jsonEncode(remote.document),
        updatedAt: remote.serverTime,
      ),
    );
    await _taskProjectionEngine.projectTasksFromSnapshot(
      noteId: id,
      snapshot: remote.document,
      userId: userId,
    );
    await (_database.update(
      _database.notes,
    )..where((note) => note.id.equals(id))).write(
      NotesCompanion(
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        isDirty: const Value(false),
        hasRemoteCopy: const Value(true),
        collapseImages: Value(json['collapse_images'] as bool? ?? false),
      ),
    );
    dev.log('[NoteCatalogSync] Hydrated $id from remote snapshot');
  }
}

final noteCatalogSyncProvider = StreamProvider.autoDispose<void>((ref) async* {
  final user = ref.watch(authControllerProvider).asData?.value;
  if (user == null) return;

  final sync = NoteCatalogSync(
    syncClient: ref.watch(noteSyncClientProvider),
    database: ref.watch(appDatabaseProvider),
  );
  while (true) {
    try {
      await sync.pullRemoteNotes(user.id);
      yield null;
    } catch (error, stackTrace) {
      dev.log(
        '[NoteCatalogSync] Pull failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await Future<void>.delayed(const Duration(seconds: 15));
  }
});
