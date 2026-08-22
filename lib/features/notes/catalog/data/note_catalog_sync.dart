import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/async/keyed_async_queue.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/catalog/model/note_icon.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';
import 'package:supanotes/features/notes/editor/document/note_document_codec.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_activity_tracker.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

typedef NoteIconUpdater =
    Future<void> Function(
      String noteId,
      NoteIcon? icon,
      DateTime? expectedUpdatedAt,
    );

final class _LocalRemoteNoteState {
  const _LocalRemoteNoteState({
    required this.existing,
    required this.localDocument,
    required this.shouldReadRemoteIcon,
  });

  final NoteData? existing;
  final LocalNoteDocumentData? localDocument;
  final bool shouldReadRemoteIcon;
}

enum _RemoteNoteWriteOutcome { applied, becameActive, stale }

final class _RemoteNoteWriteResult {
  const _RemoteNoteWriteResult(this.outcome, {this.fetchedRevision});

  final _RemoteNoteWriteOutcome outcome;
  final int? fetchedRevision;
}

enum _NoteIconPushOutcome { completed, retry }

class NoteCatalogSync {

  NoteCatalogSync({
    required NoteSyncClient syncClient,
    required AppDatabase database,
    required NoteSessionActivityTracker activityTracker,
    required NoteIconUpdater updateNoteIcon,
  }) : _syncClient = syncClient,
       _database = database,
       _activityTracker = activityTracker,
       _updateNoteIcon = updateNoteIcon;
  static const _pageSize = 100;

  final NoteSyncClient _syncClient;
  final AppDatabase _database;
  final NoteSessionActivityTracker _activityTracker;
  final NoteIconUpdater _updateNoteIcon;
  Map<String, RemoteNoteMetadata> _remoteCatalog = const {};
  final _remoteNoteQueue = KeyedAsyncQueue();

  Future<void> pushDeletedNotes() async {
    final localOnlyDeletedNotes = await _database.notesDao
        .getDirtyLocalOnlyDeletedNotes();
    for (final note in localOnlyDeletedNotes) {
      await _remoteNoteQueue.run(note.id, () async {
        if (_activityTracker.isActive(note.id)) return;
        await _database.deleteNoteData(note.id);
        dev.log('[NoteCatalogSync] Removed local-only note ${note.id}');
      });
    }

    final deletedNotes = await _database.notesDao.getDirtyDeletedNotes();
    for (final note in deletedNotes) {
      await _remoteNoteQueue.run(note.id, () async {
        if (_activityTracker.isActive(note.id)) return;
        await _syncClient.deleteNote(note.id);
        if (_activityTracker.isActive(note.id)) return;
        await _database.deleteNoteData(note.id);
        dev.log('[NoteCatalogSync] Deleted ${note.id} remotely');
      });
    }
  }

  Future<void> pushDirtyNoteIcons() async {
    final dirty = await _database.notesDao.getDirtyNoteIcons();
    for (final note in dirty) {
      await _remoteNoteQueue.run(note.id, () => _pushDirtyNoteIcon(note.id));
    }
  }

  Future<void> _pushDirtyNoteIcon(String noteId) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final outcome = await _tryPushDirtyNoteIcon(noteId);
      if (outcome == _NoteIconPushOutcome.completed) return;
    }
    throw StateError('Note icon changed while it was being synchronized');
  }

  Future<_NoteIconPushOutcome> _tryPushDirtyNoteIcon(String noteId) async {
    final note = await _database.notesDao.getNoteById(noteId);
    if (note == null || !note.noteIconDirty) {
      return _NoteIconPushOutcome.completed;
    }

    final remote = _remoteCatalog[noteId];
    if (remote != null && remote.updatedAt.isAfter(note.updatedAt)) {
      return _resolveRemoteNoteIcon(note, remote);
    }
    return _pushLocalNoteIcon(noteId, note, remote?.updatedAt);
  }

  Future<_NoteIconPushOutcome> _resolveRemoteNoteIcon(
    NoteData note,
    RemoteNoteMetadata remote,
  ) async {
    final resolved = await _database.notesDao.resolveRemoteNoteIcon(
      id: note.id,
      noteIconJson: remote.noteIconJson,
      remoteUpdatedAt: remote.updatedAt,
      expectedUpdatedAt: note.updatedAt,
      expectedNoteIconJson: note.noteIconJson,
    );
    return resolved
        ? _NoteIconPushOutcome.completed
        : _NoteIconPushOutcome.retry;
  }

  Future<_NoteIconPushOutcome> _pushLocalNoteIcon(
    String noteId,
    NoteData note,
    DateTime? remoteUpdatedAt,
  ) async {
    final icon = _decodeLocalNoteIcon(noteId, note.noteIconJson);
    try {
      await _updateNoteIcon(noteId, icon, remoteUpdatedAt);
    } catch (error, stackTrace) {
      if (!_isVersionConflict(error)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      final outcome = await _resolveVersionConflict(note);
      if (outcome != null) return outcome;
      Error.throwWithStackTrace(error, stackTrace);
    }

    await _database.notesDao.clearNoteIconDirty(
      noteId,
      note.updatedAt,
      expectedNoteIconJson: note.noteIconJson,
    );
    return _NoteIconPushOutcome.completed;
  }

  Future<_NoteIconPushOutcome?> _resolveVersionConflict(NoteData note) async {
    await _refreshRemoteCatalog();
    final latest = _remoteCatalog[note.id];
    if (latest == null) return null;
    return _resolveRemoteNoteIcon(note, latest);
  }

  bool _isVersionConflict(Object error) {
    return (error is NoteOperationsException && error.statusCode == 409) ||
        (error is DioException && error.response?.statusCode == 409);
  }

  Future<void> _refreshRemoteCatalog() async {
    final rows = await _listAllRemoteNotes();
    final remoteNotes = rows.map(RemoteNoteMetadata.fromJson).toList();
    _remoteCatalog = {for (final remote in remoteNotes) remote.id: remote};
  }

  Future<void> pullRemoteNotes(String userId) async {
    final rows = await _listAllRemoteNotes();
    final remoteNotes = rows.map(RemoteNoteMetadata.fromJson).toList();
    _remoteCatalog = {for (final remote in remoteNotes) remote.id: remote};
    final remoteIds = remoteNotes.map((note) => note.id).toSet();

    Object? firstError;
    StackTrace? firstStackTrace;
    for (final remote in remoteNotes) {
      try {
        await _pullRemoteNote(userId: userId, catalog: remote);
      } catch (error, stackTrace) {
        dev.log(
          '[NoteCatalogSync] Failed to hydrate ${remote.id}',
          error: error,
          stackTrace: stackTrace,
        );
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    await _removeMissingRemoteNotes(userId, remoteIds);
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
    dev.log('[NoteCatalogSync] Pulled ${rows.length} remote notes');
  }

  NoteIcon? _decodeLocalNoteIcon(String noteId, String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('note_icon must be an object or null');
      }
      return NoteIcon.fromJson(Map<String, dynamic>.from(decoded));
    } on Object catch (error) {
      throw FormatException('Local note icon for "$noteId" is invalid: $error');
    }
  }

  Future<List<Map<String, dynamic>>> _listAllRemoteNotes() async {
    final rows = <Map<String, dynamic>>[];
    DateTime? cursorUpdatedAt;
    String? cursorId;

    while (true) {
      final page = await _syncClient.listNotes(
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
      await _remoteNoteQueue.run(note.id, () async {
        if (_activityTracker.isActive(note.id)) return;
        await _database.deleteNoteData(note.id);
        dev.log('[NoteCatalogSync] Removed locally deleted note ${note.id}');
      });
    }
  }

  /// Hydrates one note through the authenticated document endpoint.
  ///
  /// Share-link handoff uses this entry point before routing to the normal
  /// editor. The document and its server revision are persisted by the same
  /// transaction as the catalog metadata and task projection, so the editor
  /// never starts an editable session from an unversioned public snapshot.
  Future<void> hydrateRemoteNote({
    required String userId,
    required RemoteNoteMetadata metadata,
  }) => _remoteNoteQueue.run(
    metadata.id,
    () => _hydrateRemoteNote(userId: userId, metadata: metadata),
  );

  Future<void> _hydrateRemoteNote({
    required String userId,
    required RemoteNoteMetadata metadata,
  }) async {
    final local = await _readLocalRemoteNote(metadata);
    if (_activityTracker.isActive(metadata.id)) {
      await _reuseActiveNote(userId: userId, metadata: metadata, local: local);
      return;
    }

    final result = await _fetchAndSaveRemoteNote(
      userId: userId,
      catalog: metadata,
      local: local,
    );
    switch (result.outcome) {
      case _RemoteNoteWriteOutcome.applied:
        return;
      case _RemoteNoteWriteOutcome.becameActive:
        final current = await _readLocalRemoteNote(metadata);
        await _reuseActiveNote(
          userId: userId,
          metadata: metadata,
          local: current,
        );
        return;
      case _RemoteNoteWriteOutcome.stale:
        final current = await _readLocalRemoteNote(metadata);
        if (current.localDocument != null &&
            current.existing?.isDirty == false &&
            result.fetchedRevision != null &&
            current.localDocument!.revision >= result.fetchedRevision!) {
          await _updateRemoteMetadata(
            catalog: metadata,
            shouldReadRemoteIcon: current.shouldReadRemoteIcon,
          );
          return;
        }
        throw StateError(
          'Remote note ${metadata.id} changed while its document was loading',
        );
    }
  }

  Future<void> _pullRemoteNote({
    required String userId,
    required RemoteNoteMetadata catalog,
  }) => _remoteNoteQueue.run(
    catalog.id,
    () => _pullRemoteNoteNow(userId: userId, catalog: catalog),
  );

  Future<void> _pullRemoteNoteNow({
    required String userId,
    required RemoteNoteMetadata catalog,
  }) async {
    final local = await _readLocalRemoteNote(catalog);

    if (_activityTracker.isActive(catalog.id)) {
      await _updateRemoteMetadata(
        catalog: catalog,
        shouldReadRemoteIcon: local.shouldReadRemoteIcon,
      );
      dev.log('[NoteCatalogSync] Skipping active note content ${catalog.id}');
      return;
    }

    if (local.existing != null &&
        (local.existing!.isDirty ||
            (local.existing!.hasRemoteCopy &&
                local.localDocument != null &&
                !catalog.updatedAt.isAfter(local.existing!.updatedAt)))) {
      await _updateRemoteMetadata(
        catalog: catalog,
        shouldReadRemoteIcon: local.shouldReadRemoteIcon,
      );
      return;
    }

    await _fetchAndSaveRemoteNote(
      userId: userId,
      catalog: catalog,
      local: local,
    );
  }

  Future<_LocalRemoteNoteState> _readLocalRemoteNote(
    RemoteNoteMetadata catalog,
  ) async {
    final existing = await _database.notesDao.getNoteById(catalog.id);
    final localDocument =
        await (_database.select(_database.localNoteDocuments)
              ..where((document) => document.noteId.equals(catalog.id)))
            .getSingleOrNull();
    return _LocalRemoteNoteState(
      existing: existing,
      localDocument: localDocument,
      shouldReadRemoteIcon: !(existing?.noteIconDirty ?? false),
    );
  }

  Future<void> _updateRemoteMetadata({
    required RemoteNoteMetadata catalog,
    required bool shouldReadRemoteIcon,
  }) async {
    await _database.notesDao.updateRemoteShareMetadata(
      id: catalog.id,
      permission: _permissionValueFor(catalog),
      sharedByEmail: _sharedByEmailValueFor(catalog),
      sharedByName: _sharedByNameValueFor(catalog),
      noteIconJson: _noteIconValue(catalog, apply: shouldReadRemoteIcon),
    );
  }

  Value<String?> _permissionValueFor(RemoteNoteMetadata catalog) {
    if (catalog.isOwner) {
      return const Value<String?>(null);
    }
    return Value(catalog.access == RemoteNoteAccess.edit ? 'edit' : 'view');
  }

  Value<String?> _sharedByEmailValueFor(RemoteNoteMetadata catalog) {
    if (catalog.isOwner) {
      return const Value<String?>(null);
    }
    return Value(catalog.sharedByEmail);
  }

  Value<String?> _sharedByNameValueFor(RemoteNoteMetadata catalog) {
    if (catalog.isOwner) {
      return const Value<String?>(null);
    }
    return Value(catalog.sharedByName);
  }

  Value<String?> _noteIconValue(
    RemoteNoteMetadata catalog, {
    required bool apply,
  }) {
    return apply ? Value(catalog.noteIconJson) : const Value<String?>.absent();
  }

  Future<_RemoteNoteWriteResult> _fetchAndSaveRemoteNote({
    required String userId,
    required RemoteNoteMetadata catalog,
    required _LocalRemoteNoteState local,
  }) async {
    final id = catalog.id;
    final documentResponse = await _syncClient.getDocument(id);
    if (documentResponse.noteId != id) {
      throw StateError(
        'Remote document id ${documentResponse.noteId} does not match catalog id $id',
      );
    }
    if (_activityTracker.isActive(id)) {
      dev.log('[NoteCatalogSync] Note became active during hydration $id');
      return const _RemoteNoteWriteResult(_RemoteNoteWriteOutcome.becameActive);
    }

    final projection = _projectContent(
      documentResponse.document['blocks'] as List<dynamic>? ?? [],
    );
    final documentJson = jsonEncode(documentResponse.document);
    final document = LocalNoteDocumentsCompanion.insert(
      noteId: documentResponse.noteId,
      revision: documentResponse.revision,
      documentJson: documentJson,
      updatedAt: documentResponse.serverTime,
      materializedDocumentJson: Value(documentJson),
      materializedUpdatedAt: Value(documentResponse.serverTime),
    );
    final ownerUserId = local.existing?.userId ?? userId;
    final applied = await _database.saveRemoteNote(
      noteId: id,
      mode: local.existing == null
          ? const InsertRemoteNote()
          : UpdateRemoteNote(expectedUpdatedAt: local.existing!.updatedAt),
      document: document,
      userId: userId,
      note: NotesCompanion(
        id: Value(catalog.id),
        userId: Value(ownerUserId),
        content: Value(projection.content),
        excerpt: Value(projection.excerpt),
        createdAt: Value(catalog.createdAt),
        updatedAt: Value(
          local.existing?.noteIconDirty == true
              ? local.existing!.updatedAt
              : catalog.updatedAt,
        ),
        isDirty: const Value(false),
        hasRemoteCopy: const Value(true),
        permission: _permissionValueFor(catalog),
        sharedByEmail: _sharedByEmailValueFor(catalog),
        sharedByName: _sharedByNameValueFor(catalog),
        noteIconJson: _noteIconValue(
          catalog,
          apply: local.shouldReadRemoteIcon,
        ),
        noteIconDirty: Value(local.existing?.noteIconDirty ?? false),
      ),
    );
    if (!applied) {
      dev.log('[NoteCatalogSync] Skipped stale remote hydration $id');
      return _RemoteNoteWriteResult(
        _RemoteNoteWriteOutcome.stale,
        fetchedRevision: documentResponse.revision,
      );
    }
    dev.log('[NoteCatalogSync] Hydrated $id from remote snapshot');
    return const _RemoteNoteWriteResult(_RemoteNoteWriteOutcome.applied);
  }

  Future<void> _reuseActiveNote({
    required String userId,
    required RemoteNoteMetadata metadata,
    required _LocalRemoteNoteState local,
  }) async {
    if (local.localDocument == null) {
      throw StateError(
        'Active note ${metadata.id} has no local document to reuse',
      );
    }
    await _updateRemoteMetadata(
      catalog: metadata,
      shouldReadRemoteIcon: local.shouldReadRemoteIcon,
    );
  }
}

({String content, String? excerpt}) _projectContent(List<dynamic> blocks) {
  return const NoteDocumentCodec().projectContent(blocks);
}

/// App-scoped catalog synchronization.
///
/// The root app listens to this provider so every catalog page is hydrated in
/// the background while the UI continues reading Drift. It must stay alive
/// across widget rebuilds; opening a note never waits for this provider.
final Provider<NoteCatalogSync> noteCatalogSyncServiceProvider = Provider.autoDispose<NoteCatalogSync>((
  ref,
) {
  if (ref.watch(currentUserIdProvider) == null) {
    throw StateError('NoteCatalogSync requires an authenticated user');
  }
  return NoteCatalogSync(
    syncClient: ref.watch(noteSyncClientProvider),
    database: ref.watch(appDatabaseProvider),
    activityTracker: ref.watch(noteSessionActivityTrackerProvider),
    updateNoteIcon: (noteId, icon, expectedUpdatedAt) async {
      await ref
          .read(apiClientProvider)
          .patch<Map<String, dynamic>>(
            '/notes/$noteId',
            data: {
              'note_icon': icon?.toJson(),
              if (expectedUpdatedAt != null)
                'expected_updated_at': expectedUpdatedAt
                    .toUtc()
                    .toIso8601String(),
            },
          );
    },
  );
});

final StreamProvider<void> noteCatalogSyncProvider = StreamProvider.autoDispose<void>((ref) async* {
  final user = ref.watch(authControllerProvider).asData?.value;
  if (user == null) return;

  final sync = ref.watch(noteCatalogSyncServiceProvider);
  while (true) {
    try {
      await sync.pushDeletedNotes();
      await sync.pullRemoteNotes(user.id);
      await sync.pushDirtyNoteIcons();
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
