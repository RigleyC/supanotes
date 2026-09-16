import 'dart:io';

final class AttachmentUploadResult {
  const AttachmentUploadResult({
    required this.id,
    required this.noteId,
    required this.fileName,
    required this.downloadUrl,
    required this.mimeType,
    required this.fileSize,
    required this.createdAt,
  });

  factory AttachmentUploadResult.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'Attachment upload response is not an object',
      );
    }

    String requiredString(String key) {
      final field = value[key];
      if (field is! String || field.isEmpty) {
        throw FormatException('Attachment upload response has invalid $key');
      }
      return field;
    }

    final rawSize = value['size_bytes'];
    if (rawSize is! num ||
        rawSize < 0 ||
        rawSize != rawSize.truncateToDouble()) {
      throw const FormatException(
        'Attachment upload response has invalid size_bytes',
      );
    }
    final createdAt = DateTime.tryParse(requiredString('created_at'));
    if (createdAt == null) {
      throw const FormatException(
        'Attachment upload response has invalid created_at',
      );
    }

    return AttachmentUploadResult(
      id: requiredString('id'),
      noteId: requiredString('note_id'),
      fileName: requiredString('filename'),
      downloadUrl: requiredString('download_url'),
      mimeType: requiredString('mime_type'),
      fileSize: rawSize.toInt(),
      createdAt: createdAt,
    );
  }

  final String id;
  final String noteId;
  final String fileName;
  final String downloadUrl;
  final String mimeType;
  final int fileSize;
  final DateTime createdAt;
}

abstract interface class AttachmentUploader {
  Future<AttachmentUploadResult> upload({
    required String id,
    required String noteId,
    required File file,
    required String mimeType,
  });
}
