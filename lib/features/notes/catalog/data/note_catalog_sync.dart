import 'dart:convert';
import 'dart:developer' as dev;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';
import 'package:supanotes/features/notes/domain/note_session_activity_tracker.dart';
import 'package:supanotes/features/tasks/domain/task_projection_engine.dart';

class NoteCatalogSync {
  static const _pageSize = 100;

  NoteCatalogSync({
    required NoteSyncClient syncClient,
    required AppDatabase database,
    required NoteSessionActivityTracker activityTracker,
  }) : _syncClient = syncClient,
       _database = database,
       _activityTracker = activityTracker,
       _taskProjectionEngine = TaskProjectionEngine(database: database);

  final NoteSyncClient _syncClient;
  final AppDatabase _database;
  final NoteSessionActivityTracker _activityTracker;
  final TaskProjectionEngine _taskProjectionEngine;

  Future<void> pushDeletedNotes() async {
    final localOnlyDeletedNotes = await _database.notesDao
        .getDirtyLocalOnlyDeletedNotes();
    for (final note in localOnlyDeletedNotes) {
      if (_activityTracker.isActive(note.id)) {
        continue;
      }
      await _database.deleteNoteData(note.id);
      dev.log('[NoteCatalogSync] Removed local-only note ${note.id}');
    }

    final deletedNotes = await _database.notesDao.getDirtyDeletedNotes();
    for (final note in deletedNotes) {
      if (_activityTracker.isActive(note.id)) {
        continue;
      }

      await _syncClient.deleteNote(note.id);
      if (_activityTracker.isActive(note.id)) {
        continue;
      }
      await _database.deleteNoteData(note.id);
      dev.log('[NoteCatalogSync] Deleted ${note.id} remotely');
    }
  }

  Future<void> pullRemoteNotes(String userId) async {
    final rows = await _listAllRemoteNotes();
    final remoteIds = rows.map((raw) => raw['id'] as String).toSet();

    for (final raw in rows) {
      try {
        await _pullRemoteNote(userId: userId, json: raw);
      } catch (error, stackTrace) {
        dev.log(
          '[NoteCatalogSync] Failed to hydrate ${raw['id']}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    await _removeMissingRemoteNotes(userId, remoteIds);
    dev.log('[NoteCatalogSync] Pulled ${rows.length} remote notes');
  }

  Future<List<Map<String, dynamic>>> _listAllRemoteNotes() async {
    final rows = <Map<String, dynamic>>[];
    DateTime? cursorUpdatedAt;
    String? cursorId;

    while (true) {
      final page = await _syncClient.listNotes(
        limit: _pageSize,
        cursorUpdatedAt: cursorUpdatedAt,
        cursorId: cursorId,
      );
      rows.addAll(page);
      if (page.length < _pageSize) return rows;

      final last = page.last;
      final nextUpdatedAt = DateTime.parse(last['updated_at'] as String);
      final nextId = last['id'] as String;
      if (nextUpdatedAt == cursorUpdatedAt && nextId == cursorId) {
        return rows;
      }
      cursorUpdatedAt = nextUpdatedAt;
      cursorId = nextId;
    }
  }

  Future<void> _removeMissingRemoteNotes(
    String userId,
    Set<String> remoteIds,
  ) async {
    final localRemoteNotes = await _database.notesDao.getRemoteNotes(userId);
    for (final note in localRemoteNotes) {
      if (remoteIds.contains(note.id)) {
        continue;
      }
      if (_activityTracker.isActive(note.id)) {
        continue;
      }
      await _database.deleteNoteData(note.id);
      dev.log('[NoteCatalogSync] Removed locally deleted note ${note.id}');
    }
  }

  Future<void> _pullRemoteNote({
    required String userId,
    required Map<String, dynamic> json,
  }) async {
    final id = json['id'] as String;
    final existing = await _database.notesDao.getNoteById(id);
    final hasShareMetadata =
        json.containsKey('permission') ||
        json.containsKey('shared_by_email') ||
        json.containsKey('shared_by_name');
    final permission = json['permission'] as String?;
    final sharedByEmail = json['shared_by_email'] as String?;
    final sharedByName = json['shared_by_name'] as String?;

    if (_activityTracker.isActive(id)) {
      if (existing != null && hasShareMetadata) {
        await (_database.update(
          _database.notes,
        )..where((note) => note.id.equals(id))).write(
          NotesCompanion(
            permission: Value(permission),
            sharedByEmail: Value(sharedByEmail),
            sharedByName: Value(sharedByName),
          ),
        );
      }
      dev.log('[NoteCatalogSync] Skipping active note content $id');
      return;
    }

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

    final remote = await _syncClient.getDocument(id);
    final projection = _taskProjectionEngine.projectBlocks(
      noteId: id,
      blocks: remote.document['blocks'] as List<dynamic>? ?? [],
    );
    final document = LocalNoteDocumentsCompanion.insert(
      noteId: remote.noteId,
      revision: remote.revision,
      documentJson: jsonEncode(remote.document),
      updatedAt: remote.serverTime,
    );
    if (existing == null) {
      final ownerUserId = json['user_id'] as String? ?? userId;
      await _database.saveRemoteNote(
        insertNote: true,
        document: document,
        tasks: projection.tasks,
        userId: userId,
        note: NotesCompanion.insert(
          id: id,
          userId: ownerUserId,
          content: projection.content,
          excerpt: Value(projection.excerpt),
          createdAt: createdAt,
          updatedAt: updatedAt,
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
          collapseImages: json.containsKey('collapse_images')
              ? Value(json['collapse_images'] as bool? ?? false)
              : const Value.absent(),
          permission: Value(permission),
          sharedByEmail: Value(sharedByEmail),
          sharedByName: Value(sharedByName),
        ),
      );
    } else {
      final metadata = hasShareMetadata
          ? NotesCompanion(
              permission: Value(permission),
              sharedByEmail: Value(sharedByEmail),
              sharedByName: Value(sharedByName),
            )
          : const NotesCompanion();
      await _database.saveRemoteNote(
        insertNote: false,
        document: document,
        tasks: projection.tasks,
        userId: userId,
        note: NotesCompanion(
          id: Value(id),
          content: Value(projection.content),
          excerpt: Value(projection.excerpt),
          createdAt: Value(createdAt),
          updatedAt: Value(updatedAt),
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
          collapseImages: json.containsKey('collapse_images')
              ? Value(json['collapse_images'] as bool? ?? false)
              : const Value.absent(),
          permission: metadata.permission,
          sharedByEmail: metadata.sharedByEmail,
          sharedByName: metadata.sharedByName,
        ),
      );
    }
    dev.log('[NoteCatalogSync] Hydrated $id from remote snapshot');
  }
}

final noteCatalogSyncProvider = StreamProvider.autoDispose<void>((ref) async* {
  final user = ref.watch(authControllerProvider).asData?.value;
  if (user == null) return;

  final sync = NoteCatalogSync(
    syncClient: ref.watch(noteSyncClientProvider),
    database: ref.watch(appDatabaseProvider),
    activityTracker: ref.watch(noteSessionActivityTrackerProvider),
  );
  while (true) {
    try {
      await sync.pushDeletedNotes();
      await sync.pullRemoteNotes(user.id);
      yield null;
    } catch (error, stackTrace) {
      if (error is NoteOperationsException && error.statusCode == 401) {
        dev.log('[NoteCatalogSync] Stopped (unauthenticated 401)');
        break;
      }
      dev.log(
        '[NoteCatalogSync] Pull failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await Future<void>.delayed(const Duration(seconds: 15));
  }
});
