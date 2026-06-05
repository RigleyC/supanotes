import 'package:drift/drift.dart';

import 'notes.dart';
import 'tags.dart';

/// Many-to-many junction table between [Notes] and [Tags].
///
/// Each row represents the fact that the given [noteId] has the given
/// [tagId] attached. A given note can have any number of tags, and a given
/// tag can be attached to any number of notes.
///
/// The composite primary key prevents duplicate (note, tag) pairs from
/// being created, and [isDirty] lets the sync layer know which rows need
/// to be pushed to the backend on the next sync round.
@DataClassName('LocalNoteTagData')
class LocalNoteTags extends Table {
  TextColumn get noteId => text().references(Notes, #id)();
  TextColumn get tagId => text().references(Tags, #id)();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}
