import 'package:drift/drift.dart';

@DataClassName('NoteData')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get contextId => text().nullable()();
  TextColumn get title => text().nullable()();
  TextColumn get content => text()();
  TextColumn get excerpt => text().nullable()();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get embeddingStatus => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
  BoolColumn get hasRemoteCopy =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get hideCompleted => boolean().withDefault(const Constant(false))();

  TextColumn get permission => text().nullable()();
  TextColumn get sharedByEmail => text().nullable()();
  TextColumn get sharedByName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
