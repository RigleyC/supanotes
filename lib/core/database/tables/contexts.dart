import 'package:drift/drift.dart';

@DataClassName('ContextData')
class Contexts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get slug => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
