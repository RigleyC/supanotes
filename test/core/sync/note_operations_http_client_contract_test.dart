import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import '../../helpers/auth_interceptor_test_helper.dart';

class _AllowLoopbackHttpOverrides extends HttpOverrides {}

class RealHttpTestBackend {
  late HttpServer _server;
  final Map<String, _ServerNoteState> _notes = {};
  bool failNextSyncAfterApplying = false;

  int get port => _server.port;

  int revisionOf(String noteId) => _notes[noteId]!.revision;

  int operationCount(String noteId) => _notes[noteId]!.ops.length;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handleRequest);
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }

  void seedNote(
    String noteId,
    Map<String, dynamic> docJson, {
    Map<String, String>? permissions,
  }) {
    _notes[noteId] = _ServerNoteState(
      revision: 0,
      document: docJson,
      permissions:
          permissions ??
          {'user-a': 'edit', 'user-b': 'edit', 'user-viewer': 'view'},
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final authHeader = request.headers.value('authorization') ?? '';
    final token = authHeader.replaceFirst('Bearer ', '').trim();

    if (token == 'invalid-token') {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': 'UNAUTHORIZED'}))
        ..close();
      return;
    }

    final userId = token.isEmpty ? 'anonymous' : token;

    // Match GET /api/v1/notes/:noteId/document
    if (request.method == 'GET' && path.contains('/document')) {
      final segments = path.split('/');
      final noteIdIndex = segments.indexOf('notes') + 1;
      final noteId = segments[noteIdIndex];
      final note = _notes[noteId];

      if (note == null) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'NOTE_NOT_FOUND'}))
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'noteId': noteId,
            'revision': note.revision,
            'document': note.document,
            'serverTime': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        ..close();
      return;
    }

    // Match GET /api/v1/notes/:noteId/operations
    if (request.method == 'GET' &&
        path.contains('/operations') &&
        !path.contains(':sync')) {
      final segments = path.split('/');
      final noteIdIndex = segments.indexOf('notes') + 1;
      final noteId = segments[noteIdIndex];
      final note = _notes[noteId];

      if (note == null) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'NOTE_NOT_FOUND'}))
          ..close();
        return;
      }

      final afterStr = request.uri.queryParameters['afterRevision'] ?? '0';
      final afterRev = int.tryParse(afterStr) ?? 0;
      final ops = note.ops
          .where((o) => (o['revision'] as int) > afterRev)
          .toList();

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'operations': ops,
            'revision': note.revision,
            'document': note.document,
            'serverTime': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        ..close();
      return;
    }

    // Match POST /api/v1/notes/:noteId/operations:sync
    if (request.method == 'POST' && path.contains(':sync')) {
      final segments = path.split('/');
      final noteIdIndex = segments.indexOf('notes') + 1;
      final requestNoteId = segments[noteIdIndex].replaceFirst(':sync', '');
      final requestNote = _notes[requestNoteId];

      if (requestNote == null) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'NOTE_NOT_FOUND'}))
          ..close();
        return;
      }

      final perm = requestNote.permissions[userId] ?? 'none';
      if (perm != 'edit') {
        request.response
          ..statusCode = HttpStatus.forbidden
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'FORBIDDEN'}))
          ..close();
        return;
      }

      final bodyStr = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyStr) as Map<String, dynamic>;
      final operations = (body['operations'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      final accepted = <Map<String, dynamic>>[];
      for (final op in operations) {
        final operationId = op['operationId'] as String;
        final previous = requestNote.acceptedByOperationId[operationId];
        if (previous != null) {
          accepted.add(previous);
          continue;
        }

        requestNote.revision += 1;
        final acceptedOp = {
          'operationId': operationId,
          'noteId': requestNoteId,
          'revision': requestNote.revision,
          'baseRevision': op['baseRevision'],
          'actorId': userId,
          'kind': op['kind'],
          'blockId': op['blockId'],
          'payload': op['payload'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };
        requestNote.ops.add(acceptedOp);
        final acceptedResponse = {
          'operationId': operationId,
          'revision': requestNote.revision,
          'kind': op['kind'],
          'blockId': op['blockId'],
        };
        requestNote.acceptedByOperationId[operationId] = acceptedResponse;
        accepted.add(acceptedResponse);
      }

      if (failNextSyncAfterApplying) {
        failNextSyncAfterApplying = false;
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'TEMPORARY'}))
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'accepted': accepted,
            'finalRevision': requestNote.revision,
            'canonicalDocument': requestNote.document,
            'serverTime': DateTime.now().toUtc().toIso8601String(),
          }),
        )
        ..close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..close();
  }
}

class _ServerNoteState {

  _ServerNoteState({
    required this.revision,
    required this.document,
    required this.permissions,
  });
  int revision;
  Map<String, dynamic> document;
  final Map<String, String> permissions;
  final List<Map<String, dynamic>> ops = [];
  final Map<String, Map<String, dynamic>> acceptedByOperationId = {};
}

ApiClient _createTestApiClient(String baseUrl, String userToken) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );

  final authInterceptor = buildTestAuthInterceptor(
    getAccessToken: () async => userToken,
    getRefreshToken: () async => 'refresh-token',
    saveTokens: ({required accessToken, required refreshToken}) async {},
    onAuthFailure: () async {},
    onRefresh: (_) async => null,
    replay: (options) => dio.fetch<dynamic>(options),
  );

  return ApiClient.test(authInterceptor: authInterceptor, dio: dio);
}

void main() {
  HttpOverrides.global = _AllowLoopbackHttpOverrides();

  late RealHttpTestBackend backend;

  setUp(() async {
    backend = RealHttpTestBackend();
    await backend.start();
  });

  tearDown(() async {
    await backend.stop();
  });

  test(
    'HTTP Client contract: two independent Flutter sync clients collaborate over HTTP sockets',
    () async {
      const noteId = '550e8400-e29b-41d4-a716-446655440001';
      final docJson = {
        'schemaVersion': 1,
        'blocks': [
          {'id': 'b1', 'type': 'paragraph', 'delta': [], 'metadata': {}},
        ],
      };
      backend.seedNote(noteId, docJson);

      final baseUrl = 'http://127.0.0.1:${backend.port}/api/v1/';

      final dbA = AppDatabase.test();
      final dbB = AppDatabase.test();
      addTearDown(dbA.close);
      addTearDown(dbB.close);

      final clientA = NoteSyncClient(
        client: _createTestApiClient(baseUrl, 'user-a'),
      );
      final clientB = NoteSyncClient(
        client: _createTestApiClient(baseUrl, 'user-b'),
      );

      final serviceA = NoteOperationsSyncService(
        syncClient: clientA,
        dao: dbA.noteOperationsDao,
        clientId: 'flutter-client-a',
        actorId: 'user-a',
      );

      final serviceB = NoteOperationsSyncService(
        syncClient: clientB,
        dao: dbB.noteOperationsDao,
        clientId: 'flutter-client-b',
        actorId: 'user-b',
      );

      // Seed initial local documents in Drift
      await dbA.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: 0,
          documentJson: jsonEncode(docJson),
          updatedAt: DateTime.now(),
        ),
      );
      await dbB.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: 0,
          documentJson: jsonEncode(docJson),
          updatedAt: DateTime.now(),
        ),
      );

      // Client A enqueues local edit operation and syncs over HTTP
      await serviceA.enqueueOperation(
        noteId,
        OperationRequest(
          operationId: 'op-http-1',
          baseRevision: 0,
          kind: 'text_delta',
          blockId: 'b1',
          payload: {'insert': 'Hello over HTTP'},
        ),
      );

      // Perform syncPending over real HTTP socket
      final resultA = await serviceA.syncPending(noteId);
      expect(resultA.finalRevision, equals(1));
      expect(resultA.acceptedCount, equals(1));
      expect(resultA.acceptedOperationIds, contains('op-http-1'));

      // Client B polls server over HTTP socket
      final resultB = await serviceB.pollAndReconcile(noteId);
      expect(resultB.finalRevision, equals(1));
      expect(resultB.remoteOperations, hasLength(1));
      expect(resultB.remoteOperations.first.operationId, equals('op-http-1'));
    },
  );

  test(
    'HTTP Client contract: retries a response lost after server apply without duplicating the operation',
    () async {
      const noteId = '550e8400-e29b-41d4-a716-446655440004';
      backend.seedNote(noteId, {
        'schemaVersion': 1,
        'blocks': [
          {'id': 'b1', 'type': 'paragraph', 'delta': []},
        ],
      });
      backend.failNextSyncAfterApplying = true;

      final baseUrl = 'http://127.0.0.1:${backend.port}/api/v1/';
      final db = AppDatabase.test();
      addTearDown(db.close);
      final service = NoteOperationsSyncService(
        syncClient: NoteSyncClient(
          client: _createTestApiClient(baseUrl, 'user-a'),
        ),
        dao: db.noteOperationsDao,
        clientId: 'client-retry',
        actorId: 'user-a',
      );
      await db.noteOperationsDao.upsertNoteDocument(
        LocalNoteDocumentsCompanion.insert(
          noteId: noteId,
          revision: 0,
          documentJson: jsonEncode(backend._notes[noteId]!.document),
          updatedAt: DateTime.now(),
        ),
      );
      await service.enqueueOperation(
        noteId,
        OperationRequest(
          operationId: 'op-retry-http',
          baseRevision: 0,
          kind: 'text_delta',
          blockId: 'b1',
          payload: const {'ops': []},
        ),
      );

      await expectLater(
        service.syncPending(noteId),
        throwsA(
          isA<NoteOperationsException>().having(
            (error) => error.statusCode,
            'statusCode',
            HttpStatus.serviceUnavailable,
          ),
        ),
      );
      expect(
        (await db.noteOperationsDao.getPendingOperations(noteId)).single.status,
        'in_flight',
      );

      final result = await service.syncPending(noteId);

      expect(result.finalRevision, 1);
      expect(backend.revisionOf(noteId), 1);
      expect(backend.operationCount(noteId), 1);
      expect(await db.noteOperationsDao.getPendingOperations(noteId), isEmpty);
    },
  );

  test(
    'HTTP Client contract: unauthorized token returns 401 HTTP error',
    () async {
      const noteId = '550e8400-e29b-41d4-a716-446655440002';
      backend.seedNote(noteId, {'schemaVersion': 1, 'blocks': []});

      final baseUrl = 'http://127.0.0.1:${backend.port}/api/v1/';
      final db = AppDatabase.test();
      addTearDown(db.close);

      final invalidClient = NoteSyncClient(
        client: _createTestApiClient(baseUrl, 'invalid-token'),
      );
      final service = NoteOperationsSyncService(
        syncClient: invalidClient,
        dao: db.noteOperationsDao,
        clientId: 'client-invalid',
        actorId: 'user-invalid',
      );

      await service.enqueueOperation(
        noteId,
        OperationRequest(
          operationId: 'op-invalid',
          baseRevision: 0,
          kind: 'text_delta',
          blockId: 'b1',
          payload: {},
        ),
      );

      Object? caughtError;
      try {
        await service.syncPending(noteId);
      } catch (err) {
        caughtError = err;
      }

      expect(caughtError, isNotNull);
      expect(caughtError.toString(), contains('401'));
    },
  );

  test(
    'HTTP Client contract: view permission receives 403 HTTP error when posting operations',
    () async {
      const noteId = '550e8400-e29b-41d4-a716-446655440003';
      backend.seedNote(noteId, {'schemaVersion': 1, 'blocks': []});

      final baseUrl = 'http://127.0.0.1:${backend.port}/api/v1/';
      final db = AppDatabase.test();
      addTearDown(db.close);

      final viewerClient = NoteSyncClient(
        client: _createTestApiClient(baseUrl, 'user-viewer'),
      );
      final service = NoteOperationsSyncService(
        syncClient: viewerClient,
        dao: db.noteOperationsDao,
        clientId: 'client-viewer',
        actorId: 'user-viewer',
      );

      await service.enqueueOperation(
        noteId,
        OperationRequest(
          operationId: 'op-viewer',
          baseRevision: 0,
          kind: 'text_delta',
          blockId: 'b1',
          payload: {},
        ),
      );

      Object? caughtError;
      try {
        await service.syncPending(noteId);
      } catch (err) {
        caughtError = err;
      }

      expect(caughtError, isNotNull);
      expect(caughtError.toString(), contains('403'));
    },
  );
}
