import 'package:drift/drift.dart';

@DataClassName('PendingNoteOperationData')
class PendingNoteOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get noteId => text()();

  /// Account that created the local operation.
  ///
  /// Nullable for rows created before account scoping was introduced. The
  /// sync service only adopts such rows when it can prove that the local note
  /// belongs to the current account.
  TextColumn get ownerUserId => text().nullable()();
  IntColumn get baseRevision => integer()();
  IntColumn get ordinal => integer()();
  TextColumn get kind => text()();
  TextColumn get blockId => text().nullable()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {operationId};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(note_id, owner_user_id, ordinal)',
  ];
}
