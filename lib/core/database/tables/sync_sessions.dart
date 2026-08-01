import 'package:drift/drift.dart';

@DataClassName('SyncSessionData')
class SyncSessions extends Table {
  TextColumn get noteId => text()();

  /// Account that owns this resumable sync session.
  TextColumn get ownerUserId => text().nullable()();
  IntColumn get knownRevision => integer()();
  TextColumn get operationIds => text()();
  TextColumn get startedAt => text()();

  @override
  Set<Column> get primaryKey => {noteId};
}
