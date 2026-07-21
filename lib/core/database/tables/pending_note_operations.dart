import 'package:drift/drift.dart';

@DataClassName('PendingNoteOperationData')
class PendingNoteOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get noteId => text()();
  IntColumn get baseRevision => integer()();
  IntColumn get ordinal => integer()();
  TextColumn get kind => text()();
  TextColumn get blockId => text().nullable()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {operationId};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(note_id, ordinal)',
  ];
}
