import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/tags.dart';
import '../tables/note_tags.dart';

part 'tags_dao.g.dart';

/// Drift accessor that owns reads / writes against the [Tags] and
/// [LocalNoteTags] tables.
///
/// The DAO is the single source of truth for the tag CRUD surface used by
/// the rest of the app — repositories wrap this with the [currentUserId]
/// scope, the sync layer pulls [getDirtyTags] to push, etc.
@DriftAccessor(tables: [Tags, LocalNoteTags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.db);

  final Uuid _uuid = const Uuid();

  /// Streams every tag belonging to [userId], ordered alphabetically for
  /// predictable list rendering.
  Stream<List<TagData>> watchTags(String userId) {
    return (select(tags)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  /// Returns every tag belonging to [userId] (non-streaming).
  Future<List<TagData>> getTags(String userId) {
    return (select(tags)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Streams the tags attached to the given [noteId], in the same
  /// alphabetical order as [watchTags].
  Stream<List<TagData>> watchTagsForNote(String noteId) {
    final query =
        select(tags).join([
            innerJoin(localNoteTags, localNoteTags.tagId.equalsExp(tags.id)),
          ])
          ..where(localNoteTags.noteId.equals(noteId))
          ..orderBy([
            OrderingTerm(expression: tags.name, mode: OrderingMode.asc),
          ]);
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(tags)).toList(),
    );
  }

  /// Returns the tags attached to [noteId] (non-streaming).
  Future<List<TagData>> getTagsForNote(String noteId) {
    final query =
        select(tags).join([
            innerJoin(localNoteTags, localNoteTags.tagId.equalsExp(tags.id)),
          ])
          ..where(localNoteTags.noteId.equals(noteId))
          ..orderBy([
            OrderingTerm(expression: tags.name, mode: OrderingMode.asc),
          ]);
    return query.get().then(
      (rows) => rows.map((r) => r.readTable(tags)).toList(),
    );
  }

  /// Inserts a brand-new tag owned by [userId] and returns the resulting
  /// row.
  Future<TagData> createTag({
    required String userId,
    required String name,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final companion = TagsCompanion.insert(
      id: id,
      userId: userId,
      name: name,
      createdAt: now,
      updatedAt: now,
    );
    await into(tags).insert(companion);
    return (await (select(tags)..where((t) => t.id.equals(id))).getSingle());
  }

  /// Hard-deletes a tag and any of its [LocalNoteTags] attachments.
  Future<void> deleteTag(String id) async {
    await transaction(() async {
      await (delete(localNoteTags)..where((t) => t.tagId.equals(id))).go();
      await (delete(tags)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Attaches [tagId] to [noteId]. The junction row is marked dirty so it
  /// is picked up by the next sync round.
  Future<void> attachTag({
    required String noteId,
    required String tagId,
  }) async {
    await into(localNoteTags).insertOnConflictUpdate(
      LocalNoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
    );
  }

  /// Removes the (noteId, tagId) junction row.
  Future<void> detachTag({
    required String noteId,
    required String tagId,
  }) async {
    await (delete(
      localNoteTags,
    )..where((t) => t.noteId.equals(noteId) & t.tagId.equals(tagId))).go();
  }

  /// Returns every tag that still needs to be pushed to the backend.
  Future<List<TagData>> getDirtyTags() {
    return (select(tags)..where((t) => t.isDirty.equals(true))).get();
  }

  /// Flips the dirty flag off only if the row's [updatedAt] still matches
  /// [pushedUpdatedAt] — if the user edited while the push was in flight
  /// the flag stays on so the next sync round picks up the new change.
  Future<void> clearDirtyFlag(String id, DateTime pushedUpdatedAt) async {
    await (update(tags)
          ..where((t) => t.id.equals(id) & t.updatedAt.equals(pushedUpdatedAt)))
        .write(const TagsCompanion(isDirty: Value(false)));
  }

  /// Stores a tag that came back from the backend. Uses
  /// `insertOnConflictUpdate` so a re-pulled row replaces the local copy
  /// in place, and always sets [isDirty] to `false` so the row does not
  /// get pushed back to the server.
  Future<void> upsertFromRemote(TagData tag) async {
    final incoming = tag.copyWith(isDirty: false);
    await into(tags).insertOnConflictUpdate(incoming);
  }
}
