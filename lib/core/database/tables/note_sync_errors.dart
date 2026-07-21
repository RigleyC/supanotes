import 'package:drift/drift.dart';

@DataClassName('NoteSyncErrorData')
class NoteSyncErrors extends Table {
  TextColumn get operationId => text()();
  TextColumn get noteId => text()();
  TextColumn get errorCode => text()();
  TextColumn get message => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {operationId};
}
