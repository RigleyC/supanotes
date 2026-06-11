import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/note_links.dart';

part 'note_links_dao.g.dart';

@DriftAccessor(tables: [NoteLinks])
class NoteLinksDao extends DatabaseAccessor<AppDatabase>
    with _$NoteLinksDaoMixin {
  NoteLinksDao(super.db);

  final Uuid _uuid = const Uuid();

  Future<void> createLink({
    required String sourceId,
    required String targetId,
    String? relation,
  }) async {
    final now = DateTime.now().toUtc();
    await into(noteLinks).insert(
      NoteLinksCompanion(
        id: Value(_uuid.v4()),
        sourceId: Value(sourceId),
        targetId: Value(targetId),
        relation: Value(relation ?? 'related'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<List<NoteLinkData>> getLinksForNote(String noteId) {
    return (select(noteLinks)
          ..where((t) => t.sourceId.equals(noteId) | t.targetId.equals(noteId)))
        .get();
  }

  Stream<List<NoteLinkData>> watchLinksForNote(String noteId) {
    return (select(noteLinks)
          ..where((t) => t.sourceId.equals(noteId) | t.targetId.equals(noteId)))
        .watch();
  }

  Future<void> deleteLink(String id) async {
    await (delete(noteLinks)..where((t) => t.id.equals(id))).go();
  }

  Future<List<NoteLinkData>> getDirtyLinks() {
    return (select(noteLinks)..where((t) => t.isDirty.equals(true))).get();
  }

  Future<void> clearDirtyFlag(String id) async {
    await (update(noteLinks)..where((t) => t.id.equals(id)))
        .write(const NoteLinksCompanion(isDirty: Value(false)));
  }

  Future<void> upsertFromRemote(NoteLinkData link) async {
    final incoming = link.copyWith(isDirty: false);
    await into(noteLinks).insertOnConflictUpdate(incoming);
  }
}
