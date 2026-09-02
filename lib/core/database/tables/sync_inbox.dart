import 'package:drift/drift.dart';

@DataClassName('SyncInboxData')
@TableIndex(
  name: 'idx_sync_inbox_pending',
  columns: {#userId, #appliedAt, #sequence},
)
class SyncInbox extends Table {
  TextColumn get userId => text()();
  IntColumn get sequence => integer()();
  TextColumn get type => text()();
  TextColumn get noteId => text().nullable()();
  IntColumn get revision => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get appliedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId, sequence};
}
