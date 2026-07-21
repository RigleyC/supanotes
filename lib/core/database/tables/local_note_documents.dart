import 'package:drift/drift.dart';

@DataClassName('LocalNoteDocumentData')
class LocalNoteDocuments extends Table {
  TextColumn get noteId => text()();
  IntColumn get revision => integer()();
  TextColumn get documentJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {noteId};
}
