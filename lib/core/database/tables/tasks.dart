import 'package:drift/drift.dart';

import '../../../features/tasks/domain/task_recurrence.dart';
import 'note_nodes.dart';

@DataClassName('TaskData')
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get noteId => text()();
  TextColumn get title => text()();
  TextColumn get status => text()();
  RealColumn get position => real().withDefault(const Constant(0.0))();
  TextColumn get recurrence =>
      text().map(const EnumNameConverter(TaskRecurrence.values)).nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get nodeId => text().nullable().references(NoteNodes, #id)();

  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
