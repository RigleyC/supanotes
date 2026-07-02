import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/database/database.dart';
import '../../../core/di/providers.dart';
import '../domain/attachment_model.dart';
import 'local/attachments_local_repository.dart';

class AttachmentsRepository {
  AttachmentsRepository(this._local, this._api);

  final AttachmentsLocalRepository _local;
  final ApiClient _api;

  Stream<List<AttachmentModel>> watchByNote(String noteId) => _local
      .watchByNote(noteId)
      .map((rows) => rows.map(AttachmentModel.fromData).toList());

  Stream<AttachmentModel?> watchById(String id) => _local
      .watchById(id)
      .map((row) => row != null ? AttachmentModel.fromData(row) : null);

  Future<void> upload({
    required String id,
    required String noteId,
    required File file,
    required String mimeType,
  }) async {
    final fileName = file.uri.pathSegments.last;
    final fileSize = await file.length();
    final now = DateTime.now().toUtc();

    await _local.insert(
      AttachmentsCompanion(
        id: Value(id),
        noteId: Value(noteId),
        localPath: Value(file.path),
        fileName: Value(fileName),
        mimeType: Value(mimeType),
        fileSize: Value(fileSize),
        status: const Value('uploading'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    try {
      final formData = FormData.fromMap({
        'note_id': noteId,
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final response = await _api.post<Map<String, dynamic>>(
        '/attachments/upload',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final remoteUrl = response.data!['url'] as String;
      await _local.updateRemoteUrl(id, remoteUrl);
    } catch (e) {
      await _local.updateStatus(id, 'failed');
    }
  }

  Future<void> delete(String id) => _local.delete(id);
}

final attachmentsRepositoryProvider =
    Provider.autoDispose<AttachmentsRepository>((ref) {
      final local = ref.watch(attachmentsLocalRepositoryProvider);
      final api = ref.watch(apiClientProvider);
      return AttachmentsRepository(local, api);
    });

final attachmentByIdProvider = StreamProvider.autoDispose
    .family<AttachmentModel?, String>((ref, id) {
      final repo = ref.watch(attachmentsRepositoryProvider);
      return repo.watchById(id);
    });
