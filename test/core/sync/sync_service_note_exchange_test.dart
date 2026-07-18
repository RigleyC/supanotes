import 'package:flutter_test/flutter_test.dart';

import 'package:supanotes/core/sync/sync_service.dart';

class RecordingNoteSyncTransport {
  final List<Map<String, dynamic>> requests = [];

  Future<void> sendBinaryUpdate(String noteId, List<int> update) async {
    requests.add({'noteId': noteId, 'bytes': update.length});
  }
}

SyncService buildSyncService({RecordingNoteSyncTransport? transport}) {
  throw UnimplementedError('buildSyncService not yet implemented');
}

void main() {
  group('SyncService - note exchange', () {
    test('a second idle sync sends no Yjs update', () async {
      final transport = RecordingNoteSyncTransport();
      final service = buildSyncService(transport: transport);

      await service.syncDirtyNote('note-1');
      await service.syncDirtyNote('note-1');

      expect(transport.requests, hasLength(1));
    });
  });
}
