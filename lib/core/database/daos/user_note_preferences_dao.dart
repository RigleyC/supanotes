import 'package:drift/drift.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/database/tables/user_note_preferences.dart';

part 'user_note_preferences_dao.g.dart';

@DriftAccessor(tables: [UserNotePreferences])
class UserNotePreferencesDao extends DatabaseAccessor<AppDatabase>
    with _$UserNotePreferencesDaoMixin {
  UserNotePreferencesDao(super.db);

  Stream<UserNotePreferenceData?> watchPreference(
    String userId,
    String noteId,
  ) {
    return (select(userNotePreferences)
          ..where((t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
        .watchSingleOrNull();
  }

  Future<UserNotePreferenceData?> getPreference(String userId, String noteId) {
    return (select(userNotePreferences)
          ..where((t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
        .getSingleOrNull();
  }

  Future<List<UserNotePreferenceData>> getDirtyPreferences() {
    return (select(
      userNotePreferences,
    )..where((t) => t.isDirty.equals(true))).get();
  }

  /// Clears the dirty flag only when the row's [pushedUpdatedAt] still
  /// matches — a preference edited while the push was in flight keeps its
  /// flag so the next sync round sends the newer value.
  Future<void> clearDirtyFlag(
    String userId,
    String noteId,
    DateTime pushedUpdatedAt,
  ) async {
    await (update(userNotePreferences)
          ..where(
            (t) =>
                t.userId.equals(userId) &
                t.noteId.equals(noteId) &
                t.updatedAt.equals(pushedUpdatedAt),
          ))
        .write(const UserNotePreferencesCompanion(isDirty: Value(false)));
  }

  Future<void> setFavorite(String userId, String noteId, bool favorite) =>
      _writePreference(
        userId: userId,
        noteId: noteId,
        changes: UserNotePreferencesCompanion(favorite: Value(favorite)),
      );

  Future<void> setArchived(String userId, String noteId, bool archived) =>
      _writePreference(
        userId: userId,
        noteId: noteId,
        changes: UserNotePreferencesCompanion(archived: Value(archived)),
      );

  Future<void> setHideCompleted(
    String userId,
    String noteId,
    bool hideCompleted,
  ) =>
      _writePreference(
        userId: userId,
        noteId: noteId,
        changes: UserNotePreferencesCompanion(
          hideCompleted: Value(hideCompleted),
        ),
      );

  Future<void> setCollapseImages(
    String userId,
    String noteId,
    bool collapseImages,
  ) =>
      _writePreference(
        userId: userId,
        noteId: noteId,
        changes: UserNotePreferencesCompanion(
          collapseImages: Value(collapseImages),
        ),
      );

  /// Writes all four preference fields as a single dirty row so a synced
  /// device applies and pushes them together.
  Future<void> setPreferences({
    required String userId,
    required String noteId,
    required bool favorite,
    required bool archived,
    required bool hideCompleted,
    required bool collapseImages,
  }) =>
      _writePreference(
        userId: userId,
        noteId: noteId,
        changes: UserNotePreferencesCompanion(
          favorite: Value(favorite),
          archived: Value(archived),
          hideCompleted: Value(hideCompleted),
          collapseImages: Value(collapseImages),
        ),
      );

  /// Applies a complete remote preference row, but only when the local row
  /// is clean. Returns `false` and leaves the local row untouched when an
  /// offline edit is pending so it is not lost.
  Future<bool> applyRemotePreference({
    required String userId,
    required String noteId,
    required bool favorite,
    required bool archived,
    required bool hideCompleted,
    required bool collapseImages,
    required DateTime remoteUpdatedAt,
  }) async {
    return attachedDatabase.transaction(() async {
      final local = await getPreference(userId, noteId);
      if (local != null && local.isDirty) return false;

      final remote = UserNotePreferencesCompanion(
        favorite: Value(favorite),
        archived: Value(archived),
        hideCompleted: Value(hideCompleted),
        collapseImages: Value(collapseImages),
        updatedAt: Value(remoteUpdatedAt),
        isDirty: const Value(false),
      );
      await _writeRow(
        insertion: remote.copyWith(
          userId: Value(userId),
          noteId: Value(noteId),
        ),
        update: remote,
        noteId: noteId,
      );
      return true;
    });
  }

  Future<void> _writePreference({
    required String userId,
    required String noteId,
    required UserNotePreferencesCompanion changes,
  }) async {
    final now = DateTime.now();
    final update = changes.copyWith(
      updatedAt: Value(now),
      isDirty: const Value(true),
    );
    await attachedDatabase.transaction(() async {
      await _writeRow(
        insertion: update.copyWith(
          userId: Value(userId),
          noteId: Value(noteId),
        ),
        update: update,
        noteId: noteId,
      );
    });
  }

  /// Inserts or replaces a preference row and materializes the note when the
  /// new state keeps it visible. `update` doubles as the conflict target, so
  /// a concurrent row is overwritten with the exact state being written.
  Future<void> _writeRow({
    required UserNotePreferencesCompanion insertion,
    required UserNotePreferencesCompanion update,
    required String noteId,
  }) async {
    await into(
      userNotePreferences,
    ).insert(insertion, onConflict: DoUpdate((_) => update));
    if (_anyMaterializing(update)) {
      await attachedDatabase.noteLifecycleDao.markMaterialized(noteId);
    }
  }

  bool _anyMaterializing(UserNotePreferencesCompanion changes) =>
      (changes.favorite.present && changes.favorite.value) ||
      (changes.archived.present && changes.archived.value) ||
      (changes.hideCompleted.present && changes.hideCompleted.value) ||
      (changes.collapseImages.present && changes.collapseImages.value);
}
