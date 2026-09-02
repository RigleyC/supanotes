import 'package:drift/drift.dart';

@DataClassName('SyncFeedCursorData')
class SyncFeedCursors extends Table {
  TextColumn get userId => text()();
  IntColumn get receiveCursor => integer().withDefault(const Constant(0))();
  BoolColumn get bootstrapComplete =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {userId};
}
