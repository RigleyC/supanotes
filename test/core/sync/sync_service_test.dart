import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dio/dio.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/connectivity_monitor.dart';
import 'package:supanotes/core/sync/sync_mapper.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';

class FakeApiClient extends ApiClient {
  bool pushCalled = false;
  Map<String, dynamic>? lastPayload;
  Map<String, dynamic> pullResponse = const {};

  FakeApiClient()
      : super(
          getAccessToken: () async => null,
          getRefreshToken: () async => null,
          saveTokens: ({required String accessToken, required String refreshToken}) async {},
          onAuthFailure: () async {},
        );

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    if (path == '/sync/push') {
      pushCalled = true;
      lastPayload = data as Map<String, dynamic>?;
      return Response<T>(data: null, requestOptions: RequestOptions(path: path));
    }
    if (path == '/sync/pull') {
      return Response<T>(data: pullResponse as T, requestOptions: RequestOptions(path: path));
    }
    if (path.startsWith('/sync/note/')) {
      // Yjs delta exchange — return null (no server changes) for tests
      return Response<T>(data: null, requestOptions: RequestOptions(path: path));
    }
    throw UnimplementedError();
  }
}

class FakeConnectivityMonitor implements ConnectivityMonitor {
  @override
  bool get isConnected => true;

  @override
  Stream<bool> get onConnected => const Stream.empty();

  @override
  Stream<bool> get onConnectivityChanged => const Stream.empty();

  @override
  void dispose() {}
}

void main() {
  group('SyncMapper.noteToJson', () {
    test('serializes note and includes user_id', () {
      final now = DateTime.utc(2026, 6, 15, 12, 0);
      final note = NoteData(
        id: 'note-1',
        userId: 'user-1',
        content: 'Hello World',
        createdAt: now,
        updatedAt: now,
        isDirty: true,
        hasRemoteCopy: false,
        collapseImages: false,
      );

      final json = SyncMapper().noteToJson(note);

      expect(json['user_id'], 'user-1');
      // content is no longer sent from the client; the server derives it via DB trigger
      expect(json.containsKey('content'), isFalse);
    });
  });

  group('SyncService.push', () {
    test(
      'marks pushed notes as having a remote copy and clears dirty flag',
      () async {
        SharedPreferences.setMockInitialValues({});

        final db = AppDatabase.test();
        final dao = db.notesDao;

        final now = DateTime.now().toUtc();
        await dao.createNote(
          NotesCompanion.insert(
            id: 'test-note-1',
            userId: 'test-user',
            content: 'Hello',
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(true),
            hasRemoteCopy: const Value(false),
          ),
        );

        final fakeApi = FakeApiClient();
        final connectivity = FakeConnectivityMonitor();
        final mapper = SyncMapper();
        final notifier = SyncStateNotifier();

        final service = SyncService(
          db: db,
          apiClient: fakeApi,
          mapper: mapper,
          connectivity: connectivity,
          notifier: notifier,
          yjsMgr: YjsSyncManager(db: db, userId: 'test-user'),
        );

        await service.push();

        final note = await dao.getNoteById('test-note-1');
        expect(note, isNotNull);
        expect(note!.hasRemoteCopy, isTrue);
        expect(note.isDirty, isFalse);
        expect(fakeApi.pushCalled, isTrue);

        await db.close();
      },
    );
  });

  group('SyncService.pull', () {
    test(
      'does not overwrite dirty local note fields with stale remote data',
      () async {
        SharedPreferences.setMockInitialValues({});

        final db = AppDatabase.test();
        final now = DateTime.utc(2026, 6, 17, 12);
        await db.notesDao.createNote(
          NotesCompanion.insert(
            id: 'note-1',
            userId: 'test-user',
            content: 'local content',
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(true),
            hasRemoteCopy: const Value(true),
          ),
        );

        final fakeApi = FakeApiClient()
          ..pullResponse = {
            'notes': [
              {
                'id': 'note-1',
                'user_id': 'test-user',
                'context_id': null,
                'title': null,
                'content': 'remote content',
                'excerpt': null,
                'favorite': false,
                'archived': false,
                'hide_completed': false,
                'embedding_status': null,
                'shared_permission': null,
                'shared_by_email': null,
                'shared_by_name': null,
                'created_at': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
                'deleted_at': null,
              },
            ],
          };

        final service = SyncService(
          db: db,
          apiClient: fakeApi,
          mapper: SyncMapper(),
          connectivity: FakeConnectivityMonitor(),
          notifier: SyncStateNotifier(),
          yjsMgr: YjsSyncManager(db: db, userId: 'test-user'),
        );

        await service.pull();

        final note = await db.notesDao.getNoteById('note-1');
        expect(note, isNotNull);
        expect(note!.content, 'local content');
        expect(note.isDirty, isTrue);

        await db.close();
      },
    );
  });
}
