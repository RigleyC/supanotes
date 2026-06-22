// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_note_preferences_dao.dart';

// ignore_for_file: type=lint
mixin _$UserNotePreferencesDaoMixin on DatabaseAccessor<AppDatabase> {
  $UserNotePreferencesTable get userNotePreferences =>
      attachedDatabase.userNotePreferences;
  UserNotePreferencesDaoManager get managers =>
      UserNotePreferencesDaoManager(this);
}

class UserNotePreferencesDaoManager {
  final _$UserNotePreferencesDaoMixin _db;
  UserNotePreferencesDaoManager(this._db);
  $$UserNotePreferencesTableTableManager get userNotePreferences =>
      $$UserNotePreferencesTableTableManager(
        _db.attachedDatabase,
        _db.userNotePreferences,
      );
}
