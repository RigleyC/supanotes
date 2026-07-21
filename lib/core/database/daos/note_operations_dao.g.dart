// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'note_operations_dao.dart';

// ignore_for_file: type=lint
mixin _$NoteOperationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $LocalNoteDocumentsTable get localNoteDocuments =>
      attachedDatabase.localNoteDocuments;
  $PendingNoteOperationsTable get pendingNoteOperations =>
      attachedDatabase.pendingNoteOperations;
  $NoteSyncErrorsTable get noteSyncErrors => attachedDatabase.noteSyncErrors;
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
}
