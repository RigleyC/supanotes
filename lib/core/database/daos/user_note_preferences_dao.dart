import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/user_note_preferences.dart';

part 'user_note_preferences_dao.g.dart';

@DriftAccessor(tables: [UserNotePreferences])
class UserNotePreferencesDao extends DatabaseAccessor<AppDatabase>
    with _$UserNotePreferencesDaoMixin {
  UserNotePreferencesDao(super.db);

  Stream<UserNotePreferenceData?> watchPreference(
      String userId, String noteId) {
    return (select(userNotePreferences)
          ..where(
              (t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
        .watchSingleOrNull();
  }

  Future<UserNotePreferenceData?> getPreference(
      String userId, String noteId) {
    return (select(userNotePreferences)
          ..where(
              (t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
        .getSingleOrNull();
  }

  Future<List<UserNotePreferenceData>> getDirtyPreferences() {
    return (select(userNotePreferences)
          ..where((t) => t.isDirty.equals(true)))
        .get();
  }

  Future<void> clearDirtyFlag(String userId, String noteId) async {
    await (update(userNotePreferences)
          ..where(
              (t) => t.userId.equals(userId) & t.noteId.equals(noteId)))
        .write(
      const UserNotePreferencesCompanion(isDirty: Value(false)),
    );
  }

  Future<void> setFavorite(
      String userId, String noteId, bool favorite) async {
    final now = DateTime.now();
    await into(userNotePreferences).insert(
      UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        favorite: Value(favorite),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      onConflict: DoUpdate(
        (old) => UserNotePreferencesCompanion(
          favorite: Value(favorite),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      ),
    );
  }

  Future<void> setArchived(
      String userId, String noteId, bool archived) async {
    final now = DateTime.now();
    await into(userNotePreferences).insert(
      UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        archived: Value(archived),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      onConflict: DoUpdate(
        (old) => UserNotePreferencesCompanion(
          archived: Value(archived),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      ),
    );
  }

  Future<void> setHideCompleted(
      String userId, String noteId, bool hideCompleted) async {
    final now = DateTime.now();
    await into(userNotePreferences).insert(
      UserNotePreferencesCompanion.insert(
        userId: userId,
        noteId: noteId,
        hideCompleted: Value(hideCompleted),
        updatedAt: Value(now),
        isDirty: const Value(true),
      ),
      onConflict: DoUpdate(
        (old) => UserNotePreferencesCompanion(
          hideCompleted: Value(hideCompleted),
          updatedAt: Value(now),
          isDirty: const Value(true),
        ),
      ),
    );
  }
}
