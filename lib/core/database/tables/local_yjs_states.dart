import 'package:drift/drift.dart';

import 'notes.dart';

class LocalYjsStates extends Table {
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  BlobColumn get state => blob()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {noteId};
}
