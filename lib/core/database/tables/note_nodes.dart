import 'package:drift/drift.dart';

import 'notes.dart';

class NoteNodes extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get parentId => text().nullable().references(NoteNodes, #id)();
  TextColumn get position => text().withDefault(const Constant('a0'))();
  TextColumn get type => text()();
  TextColumn get data => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
