import 'package:drift/drift.dart';

/// Local projection of the task blocks contained in each note's effective
/// (materialized) document.
///
/// Rows are rewritten when, and only when, a note's materialized document is
/// saved and its task blocks differ. Reminders and the Tasks list query this
/// table instead of decoding every note document whenever any note changes,
/// so typing in one note no longer costs work proportional to the library.
///
/// A document whose tasks cannot be read is recorded as a single row with an
/// empty [blockId] and an [invalidReason], so readers surface the error
/// instead of silently hiding that note's tasks.
@DataClassName('NoteTaskRow')
@TableIndex(name: 'idx_note_tasks_note', columns: {#noteId})
class NoteTasks extends Table {
  TextColumn get noteId => text()();
  TextColumn get blockId => text()();
  IntColumn get position => integer()();
  TextColumn get title => text()();

  /// The task block's metadata object, as stored in the document.
  TextColumn get metadataJson => text()();
  TextColumn get invalidReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {noteId, blockId};
}
