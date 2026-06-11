// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_links_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteLinksDaoMixin on DatabaseAccessor<AppDatabase> {
  $NotesTable get notes => attachedDatabase.notes;
  $NoteLinksTable get noteLinks => attachedDatabase.noteLinks;
  NoteLinksDaoManager get managers => NoteLinksDaoManager(this);
}

class NoteLinksDaoManager {
  final _$NoteLinksDaoMixin _db;
  NoteLinksDaoManager(this._db);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$NoteLinksTableTableManager get noteLinks =>
      $$NoteLinksTableTableManager(_db.attachedDatabase, _db.noteLinks);
}
