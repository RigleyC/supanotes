import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_session_activity_tracker.dart';
import 'package:supanotes/features/tasks/domain/note_document_projector.dart';
import 'package:supanotes/features/notes/catalog/model/note_icon.dart';

typedef NoteIconUpdater =
    Future<void> Function(
      String noteId,
      NoteIcon? icon,
      DateTime? expectedUpdatedAt,
    );

/// Typed metadata received from the catalog endpoint.
///
/// The catalog endpoint returns a partial note shape. The `has*` fields keep
/// the difference between an omitted field and an explicit `null`, which is
/// required for remote icon clears and partial metadata updates.
final class RemoteNoteMetadata {
  const RemoteNoteMetadata({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    required this.hasCollapseImages,
    required this.collapseImages,
    required this.hasPermission,
    required this.permission,
    required this.hasSharedByEmail,
    required this.sharedByEmail,
    required this.hasSharedByName,
    required this.sharedByName,
    required this.hasNoteIcon,
    required this.noteIcon,
  });

  factory RemoteNoteMetadata.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    return RemoteNoteMetadata(
      id: id,
      userId: _optionalString(json, 'user_id'),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      hasCollapseImages: json.containsKey('collapse_images'),
      collapseImages: _optionalBool(json, 'collapse_images'),
      hasPermission: json.containsKey('permission'),
      permission: _optionalString(json, 'permission'),
      hasSharedByEmail: json.containsKey('shared_by_email'),
      sharedByEmail: _optionalString(json, 'shared_by_email'),
      hasSharedByName: json.containsKey('shared_by_name'),
      sharedByName: _optionalString(json, 'shared_by_name'),
      hasNoteIcon: json.containsKey('note_icon'),
      noteIcon: _optionalNoteIcon(json, 'note_icon', noteId: id),
    );
  }

  final String id;
  final String? userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hasCollapseImages;
  final bool? collapseImages;
  final bool hasPermission;
  final String? permission;
  final bool hasSharedByEmail;
  final String? sharedByEmail;
  final bool hasSharedByName;
  final String? sharedByName;
  final bool hasNoteIcon;
  final NoteIcon? noteIcon;

  bool get hasShareMetadata =>
      hasPermission || hasSharedByEmail || hasSharedByName;

  bool hasShareMetadataFor(String currentUserId) =>
      hasShareMetadata || userId == currentUserId;

  String? get noteIconJson =>
      noteIcon == null ? null : jsonEncode(noteIcon!.toJson());

  Value<String?> get permissionValue =>
      hasPermission ? Value(permission) : const Value<String?>.absent();

  Value<String?> permissionValueFor(String currentUserId) =>
      userId == currentUserId ? const Value<String?>(null) : permissionValue;

  Value<String?> get sharedByEmailValue =>
      hasSharedByEmail ? Value(sharedByEmail) : const Value<String?>.absent();

  Value<String?> sharedByEmailValueFor(String currentUserId) =>
      userId == currentUserId ? const Value<String?>(null) : sharedByEmailValue;

  Value<String?> get sharedByNameValue =>
      hasSharedByName ? Value(sharedByName) : const Value<String?>.absent();

  Value<String?> sharedByNameValueFor(String currentUserId) =>
      userId == currentUserId ? const Value<String?>(null) : sharedByNameValue;

  Value<String?> noteIconValue({required bool apply}) =>
      apply ? Value(noteIconJson) : const Value<String?>.absent();

  NotesCompanion toRemoteNoteCompanion({
    required String userId,
    required String currentUserId,
    required String content,
    required String? excerpt,
    required DateTime updatedAt,
    required bool noteIconDirty,
    required bool applyNoteIcon,
  }) {
    return NotesCompanion(
      id: Value(id),
      userId: Value(userId),
      content: Value(content),
      excerpt: Value(excerpt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isDirty: const Value(false),
      hasRemoteCopy: const Value(true),
      collapseImages: hasCollapseImages
          ? Value(collapseImages ?? false)
          : const Value.absent(),
      permission: permissionValueFor(currentUserId),
      sharedByEmail: sharedByEmailValueFor(currentUserId),
      sharedByName: sharedByNameValueFor(currentUserId),
      noteIconJson: noteIconValue(apply: applyNoteIcon),
      noteIconDirty: Value(noteIconDirty),
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Remote note field "$key" must be a non-empty string');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Remote note field "$key" must be a string or null');
}

bool? _optionalBool(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('Remote note field "$key" must be a boolean or null');
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Remote note field "$key" must be an ISO date');
  }
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException catch (error) {
    throw FormatException('Remote note field "$key" is invalid: $error');
  }
}

NoteIcon? _optionalNoteIcon(
  Map<String, dynamic> json,
  String key, {
  required String noteId,
}) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! Map) {
    throw FormatException('Remote note icon for "$noteId" must be an object');
  }
  try {
    return NoteIcon.fromJson(Map<String, dynamic>.from(value));
  } on Object catch (error) {
    throw FormatException('Remote note icon for "$noteId" is invalid: $error');
  }
}

class NoteCatalogSync {
  static const _pageSize = 100;

  NoteCatalogSync({
    required NoteSyncClient syncClient,
    required AppDatabase database,
    required NoteSessionActivityTracker activityTracker,
    required NoteIconUpdater updateNoteIcon,
  }) : _syncClient = syncClient,
       _database = database,
       _activityTracker = activityTracker,
       _updateNoteIcon = updateNoteIcon,
       _documentProjector = const NoteDocumentProjector();

  final NoteSyncClient _syncClient;
  final AppDatabase _database;
  final NoteSessionActivityTracker _activityTracker;
  final NoteIconUpdater _updateNoteIcon;
  final NoteDocumentProjector _documentProjector;
  Map<String, RemoteNoteMetadata> _remoteCatalog = const {};

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

  Future<void> pushDirtyNoteIcons() async {
    final dirty = await _database.notesDao.getDirtyNoteIcons();
    for (final note in dirty) {
      final remote = _remoteCatalog[note.id];
      if (remote?.hasNoteIcon == true &&
          remote!.updatedAt.isAfter(note.updatedAt)) {
        await _database.notesDao.resolveRemoteNoteIcon(
          id: note.id,
          noteIconJson: remote.noteIconJson,
          remoteUpdatedAt: remote.updatedAt,
        );
        continue;
      }
      final icon = _decodeLocalNoteIcon(note.id, note.noteIconJson);
      try {
        await _updateNoteIcon(note.id, icon, remote?.updatedAt);
      } catch (error) {
        if (!_isVersionConflict(error)) rethrow;
        await _refreshRemoteCatalog();
        final latest = _remoteCatalog[note.id];
        if (latest == null || !latest.hasNoteIcon) rethrow;
        await _database.notesDao.resolveRemoteNoteIcon(
          id: note.id,
          noteIconJson: latest.noteIconJson,
          remoteUpdatedAt: latest.updatedAt,
        );
        continue;
      }
      await _database.notesDao.clearNoteIconDirty(note.id, note.updatedAt);
    }
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
        throw FormatException('note_icon must be an object or null');
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

  /// Hydrates one note through the authenticated document endpoint.
  ///
  /// Share-link handoff uses this entry point before routing to the normal
  /// editor. The document and its server revision are persisted by the same
  /// transaction as the catalog metadata and task projection, so the editor
  /// never starts an editable session from an unversioned public snapshot.
  Future<void> hydrateRemoteNoteFromJson({
    required String userId,
    required Map<String, dynamic> metadata,
  }) {
    return hydrateRemoteNote(
      userId: userId,
      metadata: RemoteNoteMetadata.fromJson(metadata),
    );
  }

  Future<void> hydrateRemoteNote({
    required String userId,
    required RemoteNoteMetadata metadata,
  }) async {
    final applied = await _pullRemoteNote(
      userId: userId,
      catalog: metadata,
      forceDocumentHydration: true,
    );
    if (!applied) {
      throw StateError(
        'Remote note ${metadata.id} changed while its document was loading',
      );
    }
  }

  Future<bool> _pullRemoteNote({
    required String userId,
    required RemoteNoteMetadata catalog,
    bool forceDocumentHydration = false,
  }) async {
    final id = catalog.id;
    final existing = await _database.notesDao.getNoteById(id);
    final shouldReadRemoteIcon =
        catalog.hasNoteIcon && !(existing?.noteIconDirty ?? false);
    final localDocument = await (_database.select(
      _database.localNoteDocuments,
    )..where((document) => document.noteId.equals(id))).getSingleOrNull();

    if (_activityTracker.isActive(id)) {
      if (existing != null &&
          (catalog.hasShareMetadataFor(userId) || catalog.hasNoteIcon)) {
        await _database.notesDao.updateRemoteShareMetadata(
          id: id,
          permission: catalog.permissionValueFor(userId),
          sharedByEmail: catalog.sharedByEmailValueFor(userId),
          sharedByName: catalog.sharedByNameValueFor(userId),
          noteIconJson: catalog.noteIconValue(apply: shouldReadRemoteIcon),
        );
      }
      dev.log('[NoteCatalogSync] Skipping active note content $id');
      return localDocument != null;
    }

    if (existing != null &&
        (!forceDocumentHydration &&
            (existing.isDirty ||
                (existing.hasRemoteCopy &&
                    localDocument != null &&
                    !catalog.updatedAt.isAfter(existing.updatedAt))))) {
      if (catalog.hasShareMetadataFor(userId) || catalog.hasNoteIcon) {
        await _database.notesDao.updateRemoteShareMetadata(
          id: id,
          permission: catalog.permissionValueFor(userId),
          sharedByEmail: catalog.sharedByEmailValueFor(userId),
          sharedByName: catalog.sharedByNameValueFor(userId),
          noteIconJson: catalog.noteIconValue(apply: shouldReadRemoteIcon),
        );
      }
      return false;
    }

    final documentResponse = await _syncClient.getDocument(id);
    if (documentResponse.noteId != id) {
      throw StateError(
        'Remote document id ${documentResponse.noteId} does not match catalog id $id',
      );
    }
    if (_activityTracker.isActive(id)) {
      dev.log('[NoteCatalogSync] Note became active during hydration $id');
      return localDocument != null;
    }

    final projection = _documentProjector.projectBlocks(
      noteId: id,
      blocks: documentResponse.document['blocks'] as List<dynamic>? ?? [],
    );
    final document = LocalNoteDocumentsCompanion.insert(
      noteId: documentResponse.noteId,
      revision: documentResponse.revision,
      documentJson: jsonEncode(documentResponse.document),
      updatedAt: documentResponse.serverTime,
    );
    final ownerUserId = existing?.userId ?? catalog.userId ?? userId;
    final applied = await _database.saveRemoteNote(
      noteId: id,
      mode: existing == null
          ? const InsertRemoteNote()
          : UpdateRemoteNote(expectedUpdatedAt: existing.updatedAt),
      document: document,
      tasks: projection.tasks,
      userId: userId,
      note: catalog.toRemoteNoteCompanion(
        userId: ownerUserId,
        currentUserId: userId,
        content: projection.content,
        excerpt: projection.excerpt,
        // Keep the local timestamp while an icon mutation is pending. The
        // shared metadata is then retried against the same local version and
        // cannot be mistaken for a fully accepted remote snapshot.
        updatedAt: existing?.noteIconDirty == true
            ? existing!.updatedAt
            : catalog.updatedAt,
        noteIconDirty: existing?.noteIconDirty ?? false,
        applyNoteIcon: shouldReadRemoteIcon,
      ),
    );
    if (!applied) {
      dev.log('[NoteCatalogSync] Skipped stale remote hydration $id');
      return false;
    }
    dev.log('[NoteCatalogSync] Hydrated $id from remote snapshot');
    return true;
  }
}

/// App-scoped catalog synchronization.
///
/// The root app listens to this provider so every catalog page is hydrated in
/// the background while the UI continues reading Drift. It must stay alive
/// across widget rebuilds; opening a note never waits for this provider.
final noteCatalogSyncServiceProvider = Provider.autoDispose<NoteCatalogSync>((
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

final noteCatalogSyncProvider = StreamProvider.autoDispose<void>((ref) async* {
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
