import 'package:drift/drift.dart';

@DataClassName('UserNotePreferenceData')
class UserNotePreferences extends Table {
  TextColumn get userId => text()();
  TextColumn get noteId => text()();
  BoolColumn get hideCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get filters => text().withDefault(const Constant('{}'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {userId, noteId};
}
