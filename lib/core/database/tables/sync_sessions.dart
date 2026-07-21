import 'package:drift/drift.dart';

@DataClassName('SyncSessionData')
class SyncSessions extends Table {
  TextColumn get noteId => text()();
  IntColumn get knownRevision => integer()();
  TextColumn get operationIds => text()();
  TextColumn get startedAt => text()();

  @override
  Set<Column> get primaryKey => {noteId};
}
