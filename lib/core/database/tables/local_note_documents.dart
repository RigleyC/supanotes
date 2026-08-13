import 'package:drift/drift.dart';

@DataClassName('LocalNoteDocumentData')
class LocalNoteDocuments extends Table {
  TextColumn get noteId => text()();
  IntColumn get revision => integer()();
  TextColumn get documentJson => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get materializedDocumentJson => text().nullable()();
  DateTimeColumn get materializedUpdatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {noteId};
}
