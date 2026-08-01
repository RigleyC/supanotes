import 'package:drift/drift.dart';

@DataClassName('NoteSyncErrorData')
class NoteSyncErrors extends Table {
  TextColumn get operationId => text()();
  TextColumn get noteId => text()();

  /// Account that owns the failed operation.
  ///
  /// Nullable for rows written before sync errors became account-scoped.
  TextColumn get ownerUserId => text().nullable()();
  TextColumn get errorCode => text()();
  TextColumn get message => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {operationId};
}
