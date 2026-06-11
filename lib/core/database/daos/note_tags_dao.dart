import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/note_tags.dart';

part 'note_tags_dao.g.dart';

@DriftAccessor(tables: [LocalNoteTags])
class NoteTagsDao extends DatabaseAccessor<AppDatabase>
    with _$NoteTagsDaoMixin {
  NoteTagsDao(super.db);

  Future<List<LocalNoteTagData>> getDirtyNoteTags() {
    return (select(localNoteTags)
          ..where((t) => t.isDirty.equals(true)))
        .get();
  }

  Future<void> clearDirtyFlag(String noteId, String tagId) async {
    await (update(localNoteTags)
          ..where((t) => t.noteId.equals(noteId) & t.tagId.equals(tagId)))
        .write(const LocalNoteTagsCompanion(isDirty: Value(false)));
  }

  Future<void> upsertFromRemote(LocalNoteTagData row) async {
    final incoming = row.copyWith(isDirty: false);
    await into(localNoteTags).insertOnConflictUpdate(incoming);
  }
}
