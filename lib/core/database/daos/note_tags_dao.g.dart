// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_tags_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteTagsDaoMixin on DatabaseAccessor<AppDatabase> {
  $NotesTable get notes => attachedDatabase.notes;
  $TagsTable get tags => attachedDatabase.tags;
  $LocalNoteTagsTable get localNoteTags => attachedDatabase.localNoteTags;
  NoteTagsDaoManager get managers => NoteTagsDaoManager(this);
}

class NoteTagsDaoManager {
  final _$NoteTagsDaoMixin _db;
  NoteTagsDaoManager(this._db);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$TagsTableTableManager get tags =>
      $$TagsTableTableManager(_db.attachedDatabase, _db.tags);
  $$LocalNoteTagsTableTableManager get localNoteTags =>
      $$LocalNoteTagsTableTableManager(_db.attachedDatabase, _db.localNoteTags);
}
