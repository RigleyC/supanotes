import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database.dart';
import '../../../../core/database/daos/attachments_dao.dart';

class AttachmentsLocalRepository {
  AttachmentsLocalRepository(this._dao);
  final AttachmentsDao _dao;

  Stream<List<AttachmentData>> watchByNote(String noteId) =>
      _dao.watchByNote(noteId);

  Future<List<AttachmentData>> getByNote(String noteId) =>
      _dao.getByNote(noteId);

  Future<void> insert(AttachmentsCompanion companion) => _dao.upsert(companion);

  Future<void> updateStatus(String id, String status) =>
      _dao.updateStatus(id, status);

  Future<void> updateRemoteUrl(String id, String remoteUrl) =>
      _dao.updateRemoteUrl(id, remoteUrl);

  Future<void> delete(String id) => _dao.deleteById(id);
}

final attachmentsLocalRepositoryProvider =
    Provider.autoDispose<AttachmentsLocalRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AttachmentsLocalRepository(db.attachmentsDao);
});
