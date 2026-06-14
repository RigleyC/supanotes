import 'package:drift/drift.dart';

import 'notes.dart';

/// Bidirectional link between two notes.
@DataClassName('NoteLinkData')
class NoteLinks extends Table {
  TextColumn get id => text()();
  TextColumn get sourceId => text().references(Notes, #id)();
  TextColumn get targetId => text().references(Notes, #id)();
  TextColumn get relation => text().withDefault(const Constant('related'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
