import '../../../core/database/database.dart';

enum AttachmentStatus { local, uploading, synced, failed }

enum AttachmentType { image, video, file }

class AttachmentModel {
  const AttachmentModel({
    required this.id,
    required this.noteId,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
    required this.status,
    required this.createdAt,
    this.localPath,
    this.remoteUrl,
  });

  final String id;
  final String noteId;
  final String? localPath;
  final String? remoteUrl;
  final String fileName;
  final String mimeType;
  final int fileSize;
  final AttachmentStatus status;
  final DateTime createdAt;

  AttachmentType get type {
    if (mimeType.startsWith('image/')) return AttachmentType.image;
    if (mimeType.startsWith('video/')) return AttachmentType.video;
    return AttachmentType.file;
  }

  String? get displayUrl => remoteUrl ?? localPath;

  factory AttachmentModel.fromData(AttachmentData d) => AttachmentModel(
    id: d.id,
    noteId: d.noteId,
    localPath: d.localPath,
    remoteUrl: d.remoteUrl,
    fileName: d.fileName,
    mimeType: d.mimeType,
    fileSize: d.fileSize,
    status: AttachmentStatus.values.firstWhere(
      (s) => s.name == d.status,
      orElse: () => AttachmentStatus.local,
    ),
    createdAt: d.createdAt,
  );
}
