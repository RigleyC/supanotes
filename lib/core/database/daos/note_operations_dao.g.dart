// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_operations_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteOperationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $LocalNoteDocumentsTable get localNoteDocuments =>
      attachedDatabase.localNoteDocuments;
  $PendingNoteOperationsTable get pendingNoteOperations =>
      attachedDatabase.pendingNoteOperations;
  $NoteSyncErrorsTable get noteSyncErrors => attachedDatabase.noteSyncErrors;
  $NotesTable get notes => attachedDatabase.notes;
  $SyncSessionsTable get syncSessions => attachedDatabase.syncSessions;
  $NoteTasksTable get noteTasks => attachedDatabase.noteTasks;
  $UserNotePreferencesTable get userNotePreferences =>
      attachedDatabase.userNotePreferences;
  NoteOperationsDaoManager get managers => NoteOperationsDaoManager(this);
}

class NoteOperationsDaoManager {
  final _$NoteOperationsDaoMixin _db;
  NoteOperationsDaoManager(this._db);
  $$LocalNoteDocumentsTableTableManager get localNoteDocuments =>
      $$LocalNoteDocumentsTableTableManager(
        _db.attachedDatabase,
        _db.localNoteDocuments,
      );
  $$PendingNoteOperationsTableTableManager get pendingNoteOperations =>
      $$PendingNoteOperationsTableTableManager(
        _db.attachedDatabase,
        _db.pendingNoteOperations,
      );
  $$NoteSyncErrorsTableTableManager get noteSyncErrors =>
      $$NoteSyncErrorsTableTableManager(
        _db.attachedDatabase,
        _db.noteSyncErrors,
      );
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db.attachedDatabase, _db.notes);
  $$SyncSessionsTableTableManager get syncSessions =>
      $$SyncSessionsTableTableManager(_db.attachedDatabase, _db.syncSessions);
  $$NoteTasksTableTableManager get noteTasks =>
      $$NoteTasksTableTableManager(_db.attachedDatabase, _db.noteTasks);
  $$UserNotePreferencesTableTableManager get userNotePreferences =>
      $$UserNotePreferencesTableTableManager(
        _db.attachedDatabase,
        _db.userNotePreferences,
      );
}
