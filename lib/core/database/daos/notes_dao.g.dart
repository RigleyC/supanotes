// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notes_dao.dart';

// ignore_for_file: type=lint
mixin _$NotesDaoMixin on DatabaseAccessor<AppDatabase> {
  $NotesTable get notes => attachedDatabase.notes;
  $UserNotePreferencesTable get userNotePreferences =>
      attachedDatabase.userNotePreferences;
  NotesDaoManager get managers => NotesDaoManager(this);
}

class NotesDaoManager {
  final _$NotesDaoMixin _db;
  NotesDaoManager(this._db);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$UserNotePreferencesTableTableManager get userNotePreferences =>
      $$UserNotePreferencesTableTableManager(
        _db.attachedDatabase,
        _db.userNotePreferences,
      );
}
