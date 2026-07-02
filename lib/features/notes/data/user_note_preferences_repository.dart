import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/current_user.dart';
import '../../../core/database/database.dart';

class UserNotePreferencesRepository {
  UserNotePreferencesRepository(this._db);
  final AppDatabase _db;

  Stream<UserNotePreferenceData?> watchPreference(
    String userId,
    String noteId,
  ) {
    return _db.userNotePreferencesDao.watchPreference(userId, noteId);
  }

  Future<void> setFavorite(String userId, String noteId, bool favorite) {
    return _db.userNotePreferencesDao.setFavorite(userId, noteId, favorite);
  }

  Future<void> setArchived(String userId, String noteId, bool archived) {
    return _db.userNotePreferencesDao.setArchived(userId, noteId, archived);
  }

  Future<void> setHideCompleted(
    String userId,
    String noteId,
    bool hideCompleted,
  ) {
    return _db.userNotePreferencesDao.setHideCompleted(
      userId,
      noteId,
      hideCompleted,
    );
  }
}

final userNotePreferencesRepositoryProvider =
    Provider.autoDispose<UserNotePreferencesRepository>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return UserNotePreferencesRepository(db);
    });

final userNotePreferenceStreamProvider = StreamProvider.autoDispose
    .family<UserNotePreferenceData?, String>((ref, noteId) {
      final userId = ref.watch(currentUserIdProvider);
      if (userId == null) return Stream.value(null);
      return ref
          .watch(userNotePreferencesRepositoryProvider)
          .watchPreference(userId, noteId);
    });
