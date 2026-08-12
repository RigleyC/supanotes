import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/attachments.dart';

part 'attachments_dao.g.dart';

@DriftAccessor(tables: [Attachments])
class AttachmentsDao extends DatabaseAccessor<AppDatabase>
    with _$AttachmentsDaoMixin {
  AttachmentsDao(super.db);

  Stream<List<AttachmentData>> watchByNote(String noteId) =>
      (select(attachments)..where((a) => a.noteId.equals(noteId))).watch();

  Future<List<AttachmentData>> getByNote(String noteId) =>
      (select(attachments)..where((a) => a.noteId.equals(noteId))).get();

  Stream<AttachmentData?> watchById(String id) =>
      (select(attachments)..where((a) => a.id.equals(id))).watchSingleOrNull();

  Future<void> upsert(AttachmentsCompanion companion) async {
    await attachedDatabase.transaction(() async {
      await into(attachments).insertOnConflictUpdate(companion);
      if (companion.noteId.present) {
        await attachedDatabase.noteLifecycleDao.markMaterialized(
          companion.noteId.value,
        );
      }
    });
  }

  Future<void> updateStatus(String id, String status) =>
      (update(attachments)..where((a) => a.id.equals(id))).write(
        AttachmentsCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> updateRemoteUrl(String id, String remoteUrl) =>
      (update(attachments)..where((a) => a.id.equals(id))).write(
        AttachmentsCompanion(
          remoteUrl: Value(remoteUrl),
          status: const Value('synced'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> deleteById(String id) =>
      (delete(attachments)..where((a) => a.id.equals(id))).go();
}
