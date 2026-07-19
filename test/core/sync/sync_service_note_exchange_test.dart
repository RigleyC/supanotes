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
  Map<String, dynamic>? lastPushPayload;
  int exchangeCallCount = 0;
  int exchangeFailAfter = 0;
  int exchangeFailCount = 0;

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    if (path == '/sync/push') {
      lastPushPayload = data as Map<String, dynamic>?;
      requests.add({'path': path});
      return Response<T>(data: null, requestOptions: RequestOptions(path: path));
    }

    if (path == '/sync/pull') {
      requests.add({'path': path});
      return Response<T>(data: <String, dynamic>{} as T, requestOptions: RequestOptions(path: path));
    }

    if (path.startsWith('/sync/note/')) {
      final noteId = path.split('/').last;
      exchangeCallCount++;

      if (exchangeFailCount < exchangeFailAfter) {
        exchangeFailCount++;
        throw DioException(requestOptions: RequestOptions(path: path));
      }

      int bodyLength = 0;
      if (data is Stream) {
        try {
          final bytes = await data.first;
          bodyLength = bytes is List<int> ? bytes.length : 0;
        } catch (_) {}
      }
      requests.add({
        'path': path,
        'noteId': noteId,
        'bodyLength': bodyLength,
      });
      return Response<T>(data: <int>[] as T, requestOptions: RequestOptions(path: path));
    }

    throw UnimplementedError('Unexpected path: $path');
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
  required ApiClient apiClient,
}) {
  return SyncService(
    db: db,
    apiClient: apiClient,
    mapper: SyncMapper(),
    connectivity: FakeConnectivity(),
    notifier: SyncStateNotifier(),
    yjsMgr: YjsSyncManager(db: db, userId: 'test-user'),
  );
}

Future<String> insertNote(AppDatabase db, String id) async {
  final now = DateTime.now().toUtc();
  await db.into(db.notes).insert(
    NotesCompanion.insert(
      id: id,
      userId: 'test-user',
      content: '',
      createdAt: now,
      updatedAt: now,
      isDirty: const Value(false),
      hasRemoteCopy: const Value(true),
    ),
  );
  return id;
}

void main() {
  group('SyncService - note exchange', () {
    test('syncDirtyNote queues per-note sync correctly', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final transport = RecordingApiClient();
      final service = buildSyncService(db: db, apiClient: transport);

      await insertNote(db, 'note-1');
      await service.syncDirtyNote('note-1');

      expect(transport.requests, hasLength(1));
      expect(transport.requests.first['path'], '/sync/note/note-1');

      await service.syncDirtyNote('note-1');
      await db.close();
    });

    test('two notes sync in parallel but same note is serialized', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final transport = RecordingApiClient();
      final service = buildSyncService(db: db, apiClient: transport);

      await insertNote(db, 'note-a');
      await insertNote(db, 'note-b');

      // Sync two different notes concurrently — both must complete.
      await Future.wait([
        service.syncDirtyNote('note-a'),
        service.syncDirtyNote('note-b'),
      ]);

      final noteAReqs = transport.requests
          .where((r) => r['noteId'] == 'note-a')
          .toList();
      final noteBReqs = transport.requests
          .where((r) => r['noteId'] == 'note-b')
          .toList();

      expect(noteAReqs, hasLength(1), reason: 'note-a must have completed');
      expect(noteBReqs, hasLength(1), reason: 'note-b must have completed');

      await db.close();
    });

    test('same note serializes concurrent syncDirtyNote calls', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final transport = RecordingApiClient();
      final service = buildSyncService(db: db, apiClient: transport);

      await insertNote(db, 'note-serial');

      // Fail first exchange to see serialization.
      transport.exchangeFailAfter = 1;

      await Future.wait([
        service.syncDirtyNote('note-serial').catchError((_) {}),
        service.syncDirtyNote('note-serial'),
      ]);

      final noteReqs =
          transport.requests.where((r) => r['noteId'] == 'note-serial').toList();
      expect(noteReqs, hasLength(1), reason: 'only one exchange should have succeeded');

      await db.close();
    });

    test('exchange failure does not poison the chain', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final transport = RecordingApiClient();
      final service = buildSyncService(db: db, apiClient: transport);

      await insertNote(db, 'note-chain');

      // First two exchanges fail; third succeeds.
      transport.exchangeFailAfter = 2;

      expect(
        () => service.syncDirtyNote('note-chain'),
        throwsA(isA<DioException>()),
      );

      expect(
        () => service.syncDirtyNote('note-chain'),
        throwsA(isA<DioException>()),
      );

      // Third call — chain must not be broken.
      await service.syncDirtyNote('note-chain');

      expect(transport.exchangeCallCount, 3, reason: 'all three calls must have been attempted');
      await db.close();
    });

    test('vector unchanged on exchange failure', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final transport = RecordingApiClient();
      final service = buildSyncService(db: db, apiClient: transport);

      await insertNote(db, 'note-vec');

      // First exchange succeeds — vector is persisted.
      await service.syncDirtyNote('note-vec');

      final stateAfterSuccess = await (db.select(db.localYjsStates)
            ..where((t) => t.noteId.equals('note-vec')))
          .getSingleOrNull();
      final vectorAfterSuccess = stateAfterSuccess?.syncedStateVector;
      expect(vectorAfterSuccess, isNotNull, reason: 'vector should be persisted after success');

      // Second exchange fails.
      transport.exchangeFailAfter = 1;

      expect(
        () => service.syncDirtyNote('note-vec'),
        throwsA(isA<DioException>()),
      );

      // Vector must be unchanged (still the one from the first successful exchange).
      final stateAfterFailure = await (db.select(db.localYjsStates)
            ..where((t) => t.noteId.equals('note-vec')))
          .getSingleOrNull();
      expect(
        stateAfterFailure?.syncedStateVector?.toList(),
        vectorAfterSuccess?.toList(),
        reason: 'vector must not change after a failed exchange',
      );

      await db.close();
    });

    test('push payload does not contain note_yjs_states', () async {
      SharedPreferences.setMockInitialValues({});

      final db = AppDatabase.test();
      final transport = RecordingApiClient();
      final service = buildSyncService(db: db, apiClient: transport);

      final now = DateTime.now().toUtc();
      await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: 'push-note',
          userId: 'test-user',
          content: '',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(true),
          hasRemoteCopy: const Value(false),
        ),
      );

      await service.push();

      expect(transport.lastPushPayload, isNotNull, reason: 'push must have been called');
      expect(
        transport.lastPushPayload!.containsKey('note_yjs_states'),
        isFalse,
        reason: 'push payload must not contain note_yjs_states',
      );

      await db.close();
    });
  });
}
