import 'package:drift/drift.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/features/notes/catalog/data/note_catalog_sync.dart';
import 'package:supanotes/features/notes/catalog/model/remote_note_metadata.dart';

/// Applies one note's catalog state without replacing an already-versioned
/// local document.
///
/// Full document hydration is reserved for notes that do not exist locally
/// yet. Existing documents are reconciled by the REST/OT sync service, which
/// preserves canonical + pending local operations.
final class RemoteNoteChangeApplier {
  const RemoteNoteChangeApplier({
    required AppDatabase database,
    required NoteCatalogSync catalogSync,
    required String userId,
  }) : _database = database,
       _catalogSync = catalogSync,
       _userId = userId;

  final AppDatabase _database;
  final NoteCatalogSync _catalogSync;
  final String _userId;

  Future<void> apply(RemoteNoteMetadata metadata) async {
    final existing = await _database.notesDao.getNoteById(metadata.id);
    final localDocument =
        await (_database.select(_database.localNoteDocuments)
              ..where((document) => document.noteId.equals(metadata.id)))
            .getSingleOrNull();

    if (existing == null || localDocument == null) {
      await _catalogSync.hydrateRemoteNote(
        userId: _userId,
        metadata: metadata,
      );
      return;
    }

    await _database.transaction(() async {
      await _database.notesDao.updateRemoteShareMetadata(
        id: metadata.id,
        permission: _permission(metadata),
        sharedByEmail: _sharedByEmail(metadata),
        sharedByName: _sharedByName(metadata),
        noteIconJson: Value(metadata.noteIconJson),
      );
      await _database.userNotePreferencesDao.applyRemotePreference(
        userId: _userId,
        noteId: metadata.id,
        favorite: metadata.favorite,
        archived: metadata.archived,
        hideCompleted: metadata.hideCompleted,
        collapseImages: metadata.collapseImages,
        remoteUpdatedAt: metadata.updatedAt,
      );

      if (!existing.noteIconDirty &&
          metadata.updatedAt.isAfter(existing.updatedAt)) {
        await (_database.update(_database.notes)
              ..where((note) => note.id.equals(metadata.id)))
            .write(NotesCompanion(updatedAt: Value(metadata.updatedAt)));
      }
    });
  }

  Value<String?> _permission(RemoteNoteMetadata metadata) {
    if (metadata.isOwner) return const Value(null);
    return Value(
      metadata.access == RemoteNoteAccess.edit ? 'edit' : 'view',
    );
  }

  Value<String?> _sharedByEmail(RemoteNoteMetadata metadata) {
    return metadata.isOwner
        ? const Value(null)
        : Value(metadata.sharedByEmail);
  }

  Value<String?> _sharedByName(RemoteNoteMetadata metadata) {
    return metadata.isOwner
        ? const Value(null)
        : Value(metadata.sharedByName);
  }
}
