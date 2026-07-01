import 'package:drift/drift.dart';

import 'notes.dart';

class NoteNodes extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get parentId => text().nullable().references(NoteNodes, #id)();
  IntColumn get position => integer()();
  TextColumn get type => text()();
  TextColumn get data => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
