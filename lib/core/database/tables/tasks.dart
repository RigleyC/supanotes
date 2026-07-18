import 'package:drift/drift.dart';

import '../../../features/tasks/domain/task_recurrence.dart';

@DataClassName('TaskData')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get noteId => text()();
  TextColumn get title => text()();
  TextColumn get status => text()();
  TextColumn get position => text().withDefault(const Constant('a0'))();
  TextColumn get recurrence =>
      text().map(const EnumNameConverter(TaskRecurrence.values)).nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get hasTime => boolean().withDefault(const Constant(false))();
  TextColumn get reminder => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
