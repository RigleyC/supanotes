import 'package:drift/drift.dart';

/// Local copy of an independently-owned task.
///
/// Task blocks that live inside note documents do not belong in this table.
/// Their canonical state remains the REST/OT document snapshot.
@DataClassName('TaskData')
@TableIndex(
  name: 'idx_tasks_owner_agenda',
  columns: {#ownerUserId, #deletedAt, #dueDate},
)
@TableIndex(
  name: 'idx_tasks_owner_updated',
  columns: {#ownerUserId, #updatedAt},
)
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get ownerUserId => text()();
  TextColumn get title => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get hasTime => boolean().withDefault(const Constant(false))();
  TextColumn get recurrenceRule => text().nullable()();
  TextColumn get reminder => text().nullable()();

  /// Canonical JSON object containing scheduledAt -> completedAt entries.
  TextColumn get completions => text().withDefault(const Constant('{}'))();
  TextColumn get completionHistory =>
      text().withDefault(const Constant('[]'))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastCompletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get scheduleGeneration =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Durable local outbox for mutations of independently-owned tasks.
@DataClassName('PendingTaskOperationData')
@TableIndex(
  name: 'idx_pending_task_operations_task_order',
  columns: {#taskId, #ordinal},
)
@TableIndex(
  name: 'idx_pending_task_operations_owner_status',
  columns: {#ownerUserId, #status, #createdAt},
)
class PendingTaskOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get taskId => text()();
  TextColumn get ownerUserId => text()();
  IntColumn get observedRevision => integer()();
  IntColumn get scheduleGeneration => integer()();
  IntColumn get ordinal => integer()();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text()();
  TextColumn get payloadHash => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {operationId};

  @override
  List<String> get customConstraints => const [
    'UNIQUE(task_id, ordinal)',
  ];
}

/// Why the independent-task resource may be unavailable on this device.
enum TaskStorageAvailability { available, blocked }

/// Read-only diagnostic exposed by [AppDatabase] and the DI layer.
///
/// A blocked task resource is intentionally independent from note sync errors:
/// note data and its outbox can continue operating while a quarantined legacy
/// task table is retained for an explicit export/retention decision.
class TaskStorageDiagnostic {
  const TaskStorageDiagnostic({
    this.availability = TaskStorageAvailability.available,
    this.quarantinedRows = const <String, int>{},
  });

  final TaskStorageAvailability availability;
  final Map<String, int> quarantinedRows;

  bool get isAvailable => availability == TaskStorageAvailability.available;
  bool get isBlocked => !isAvailable;
  bool get hasQuarantinedRows =>
      quarantinedRows.values.any((count) => count > 0);
}
