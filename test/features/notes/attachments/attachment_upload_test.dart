import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/features/notes/attachments/domain/attachment_upload.dart';

void main() {
  test('decodes the Go upload response including download_url', () {
    final result = AttachmentUploadResult.fromJson(const {
      'id': 'remote-1',
      'note_id': 'note-1',
      'filename': 'receipt.pdf',
      'download_url': '/api/v1/attachments/remote-1/content',
      'mime_type': 'application/pdf',
      'size_bytes': 42,
      'created_at': '2026-09-16T12:00:00Z',
    });

    expect(result.id, 'remote-1');
    expect(result.downloadUrl, '/api/v1/attachments/remote-1/content');
    expect(result.fileSize, 42);
  });

  test('rejects the legacy untyped url response', () {
    expect(
      () => AttachmentUploadResult.fromJson(const {
        'id': 'remote-1',
        'note_id': 'note-1',
        'filename': 'receipt.pdf',
        'url': '/attachments/remote-1',
        'mime_type': 'application/pdf',
        'size_bytes': 42,
        'created_at': '2026-09-16T12:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test('rejects fractional and negative sizes', () {
    final base = <String, dynamic>{
      'id': 'remote-1',
      'note_id': 'note-1',
      'filename': 'receipt.pdf',
      'download_url': '/attachments/remote-1',
      'mime_type': 'application/pdf',
      'created_at': '2026-09-16T12:00:00Z',
    };

    expect(
      () => AttachmentUploadResult.fromJson({...base, 'size_bytes': -1}),
      throwsFormatException,
    );
    expect(
      () => AttachmentUploadResult.fromJson({...base, 'size_bytes': 1.5}),
      throwsFormatException,
    );
  });
}
