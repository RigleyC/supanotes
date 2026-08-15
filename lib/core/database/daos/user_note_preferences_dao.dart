import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/user_note_preferences.dart';

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

  Future<void> setFavorite(String userId, String noteId, bool favorite) async {
    final now = DateTime.now();
    await _writePreference(
      noteId: noteId,
      materialized: favorite,
      insertion: UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        favorite: Value(favorite),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      update: UserNotePreferencesCompanion(
        favorite: Value(favorite),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> setArchived(String userId, String noteId, bool archived) async {
    final now = DateTime.now();
    await _writePreference(
      noteId: noteId,
      materialized: archived,
      insertion: UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        archived: Value(archived),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      update: UserNotePreferencesCompanion(
        archived: Value(archived),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> setHideCompleted(
    String userId,
    String noteId,
    bool hideCompleted,
  ) async {
    final now = DateTime.now();
    await _writePreference(
      noteId: noteId,
      materialized: hideCompleted,
      insertion: UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        hideCompleted: Value(hideCompleted),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      update: UserNotePreferencesCompanion(
        hideCompleted: Value(hideCompleted),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

  Future<void> setCollapseImages(
    String userId,
    String noteId,
    bool collapseImages,
  ) async {
    final now = DateTime.now();
    await _writePreference(
      noteId: noteId,
      materialized: collapseImages,
      insertion: UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        collapseImages: Value(collapseImages),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      update: UserNotePreferencesCompanion(
        collapseImages: Value(collapseImages),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

  /// Writes all four preference fields as a single dirty row so a synced
  /// device applies and pushes them together.
  Future<void> setPreferences({
    required String userId,
    required String noteId,
    required bool favorite,
    required bool archived,
    required bool hideCompleted,
    required bool collapseImages,
  }) async {
    final now = DateTime.now();
    await _writePreference(
      noteId: noteId,
      materialized: favorite || archived || hideCompleted || collapseImages,
      insertion: UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        favorite: Value(favorite),
        archived: Value(archived),
        hideCompleted: Value(hideCompleted),
        collapseImages: Value(collapseImages),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      update: UserNotePreferencesCompanion(
        favorite: Value(favorite),
        archived: Value(archived),
        hideCompleted: Value(hideCompleted),
        collapseImages: Value(collapseImages),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
    );
  }

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

      final update = UserNotePreferencesCompanion(
        favorite: Value(favorite),
        archived: Value(archived),
        hideCompleted: Value(hideCompleted),
        collapseImages: Value(collapseImages),
        updatedAt: Value(remoteUpdatedAt),
        isDirty: const Value(false),
      );
      await into(userNotePreferences)
          .insert(
            UserNotePreferencesCompanion.insert(
              userId: userId,
              noteId: noteId,
              favorite: Value(favorite),
              archived: Value(archived),
              hideCompleted: Value(hideCompleted),
              collapseImages: Value(collapseImages),
              updatedAt: Value(remoteUpdatedAt),
              isDirty: const Value(false),
            ),
            onConflict: DoUpdate((_) => update),
          );

      if (favorite || archived || hideCompleted || collapseImages) {
        await attachedDatabase.noteLifecycleDao.markMaterialized(noteId);
      }
      return true;
    });
  }

  Future<void> _writePreference({
    required String noteId,
    required bool materialized,
    required UserNotePreferencesCompanion insertion,
    required UserNotePreferencesCompanion update,
  }) async {
    await attachedDatabase.transaction(() async {
      await into(
        userNotePreferences,
      ).insert(insertion, onConflict: DoUpdate((_) => update));
      if (materialized) {
        await attachedDatabase.noteLifecycleDao.markMaterialized(noteId);
      }
    });
  }
}
