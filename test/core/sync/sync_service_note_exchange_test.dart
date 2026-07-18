import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/connectivity_monitor.dart';
import 'package:supanotes/core/sync/sync_mapper.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

class RecordingApiClient extends ApiClient {
  RecordingApiClient()
      : super(
          getAccessToken: () async => null,
          getRefreshToken: () async => null,
          saveTokens: ({required String accessToken, required String refreshToken}) async {},
          onAuthFailure: () async {},
        );

  final List<Map<String, dynamic>> requests = [];

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    int bodyLength = 0;
    if (data is Stream) {
      try {
        final bytes = await data.first;
        bodyLength = bytes is List<int> ? bytes.length : 0;
      } catch (_) {}
    }
    requests.add({
      'path': path,
      'bodyLength': bodyLength,
    });
    // Return null data — SyncService checks for null/empty before processing
    return Response<T>(data: null, requestOptions: RequestOptions(path: path));
  }
}

class FakeConnectivity implements ConnectivityMonitor {
  @override
  bool get isConnected => true;

  @override
  Stream<bool> get onConnected => const Stream.empty();

  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();

  @override
  void dispose() {}
}

SyncService buildSyncService({
  required AppDatabase db,
  RecordingApiClient? transport,
}) {
  final api = transport ?? RecordingApiClient();
  return SyncService(
    db: db,
    apiClient: api,
    mapper: SyncMapper(),
    connectivity: FakeConnectivity(),
    notifier: SyncStateNotifier(),
    yjsMgr: YjsSyncManager(db: db, userId: 'test-user'),
  );
}

void main() {
  group('SyncService - note exchange', () {
    test('syncDirtyNote queues per-note sync correctly', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final transport = RecordingApiClient();
      final service = buildSyncService(db: db, transport: transport);

      // Create the note first to satisfy FOREIGN KEY constraints
      final now = DateTime.now().toUtc();
      await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: 'note-1',
          userId: 'test-user',
          content: '',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ),
      );

      await service.syncDirtyNote('note-1');

      // The first sync sends an update
      expect(transport.requests, hasLength(1));
      expect(transport.requests.first['path'], '/sync/note/note-1');

      // Add a second Yjs state so the chain has something to work with
      await service.syncDirtyNote('note-1');

      await db.close();
    });
  });
}
