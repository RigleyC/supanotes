import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_editor/super_editor.dart';
import 'package:yjs_dart/yjs_dart.dart';

import 'package:supanotes/core/api/api_client.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/connectivity_monitor.dart';
import 'package:supanotes/core/sync/sync_mapper.dart';
import 'package:supanotes/core/sync/sync_service.dart';
import 'package:supanotes/core/sync/sync_state.dart';
import 'package:supanotes/core/sync/yjs_sync_manager.dart';
import 'package:supanotes/features/notes/domain/yjs_node_codec.dart';
import 'package:supanotes/features/notes/presentation/controllers/note_editor_controller.dart';

class ControllableApiClient extends ApiClient {
  ControllableApiClient()
      : super(
          getAccessToken: () async => null,
          getRefreshToken: () async => null,
          saveTokens: ({required String accessToken, required String refreshToken}) async {},
          onAuthFailure: () async {},
        );

  final List<Uint8List> exchangeBodies = [];

  /// If set, exchange POST awaits this completer before returning.
  Completer<void>? holdResponse;

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    if (path == '/sync/push' || path == '/sync/pull') {
      return Response<T>(data: null, requestOptions: RequestOptions(path: path));
    }
    if (path.startsWith('/sync/note/')) {
      if (data is Stream) {
        try {
          final bytes = await data.first;
          if (bytes is List<int>) {
            exchangeBodies.add(Uint8List.fromList(bytes));
          }
        } catch (_) {}
      }
      if (holdResponse != null) {
        await holdResponse!.future;
      }
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
  required YjsSyncManager yjsMgr,
}) {
  return SyncService(
    db: db,
    apiClient: apiClient,
    mapper: SyncMapper(),
    connectivity: FakeConnectivity(),
    notifier: SyncStateNotifier(),
    yjsMgr: yjsMgr,
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

void seedDocWithParagraphs(Doc doc, List<Map<String, String>> paragraphs) {
  doc.transact((txn) {
    final nodesMap = doc.getMap<Object>('nodes')!;
    for (final p in paragraphs) {
      final id = p['id']!;
      final text = p['text']!;
      final pos = p['position']!;
      nodesMap.set(
        id,
        '{"id":"$id","position":"$pos","type":"paragraph","data":{"text":"$text"}}',
      );
      doc.getText('content/$id')!.insert(0, text);
    }
  });
}

void main() {
  group('Sync regression — edit during in-flight exchange', () {
    test('edit during HTTP keeps dirty flag and re-sends on next exchange',
        () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.test();
      final api = ControllableApiClient();
      final mgr = YjsSyncManager(db: db, userId: 'test-user');
      final service = buildSyncService(db: db, apiClient: api, yjsMgr: mgr);

      await insertNote(db, 'race-note');

      // Seed initial content and establish synced state vector.
      final doc = await mgr.loadDoc('race-note');
      doc.transact((txn) {
        doc.getMap<Object>('nodes')!.set(
          'p1',
          '{"id":"p1","position":"a0","type":"paragraph","data":{"text":"initial"}}',
        );
        doc.getText('content/p1')!.insert(0, 'initial');
      });
      final initialSV = encodeStateVector(doc);
      await mgr.persistWithSyncedVector('race-note', initialSV);

      // Hold the exchange HTTP so we can mutate during it.
      api.holdResponse = Completer<void>();

      service.markDirty('race-note');
      final exchange1Future = service.syncDirtyNote('race-note');

      // Yield enough for the exchange to reach the HTTP hold point.
      for (int i = 0; i < 5; i++) {
        await Future.delayed(Duration.zero);
      }

      // --- Mutate the YDoc during the held HTTP ---
      doc.transact((txn) {
        doc.getMap<Object>('nodes')!.set(
          'p2',
          '{"id":"p2","position":"b0","type":"paragraph","data":{"text":"edited during HTTP"}}',
        );
        doc.getText('content/p2')!.insert(0, 'edited during HTTP');
      });

      // Mark dirty again (bumps generation — what the provider does).
      service.markDirty('race-note');

      // Release the response.
      api.holdResponse!.complete();
      await exchange1Future;

      // After exchange1: SV must NOT have advanced (gen changed during flight).
      final state1 = await (db.select(db.localYjsStates)
        ..where((t) => t.noteId.equals('race-note'))).getSingleOrNull();
      expect(state1, isNotNull);
      expect(state1!.syncedStateVector, equals(initialSV),
        reason: 'SV must NOT advance after exchange with concurrent edit');

      // Second exchange: body must contain the mutation.
      api.exchangeBodies.clear();
      service.markDirty('race-note');
      await service.syncDirtyNote('race-note');

      expect(api.exchangeBodies, hasLength(1),
        reason: 'Second exchange must send a non-empty body');
      final verify = Doc();
      applyUpdate(verify, api.exchangeBodies[0]);
      expect(verify.getText('content/p2')!.toString(), 'edited during HTTP',
        reason: 'Mutation made during held HTTP must appear in second exchange');

      // SV advanced after successful second exchange.
      final state2 = await (db.select(db.localYjsStates)
        ..where((t) => t.noteId.equals('race-note'))).getSingleOrNull();
      expect(state2!.syncedStateVector, isNot(equals(initialSV)),
        reason: 'SV must advance after successful exchange');

      await db.close();
    });
  });

  group('Sync regression — save on dispose before debounce', () {
    test('dispose triggers persist before 500ms debounce fires',
        () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.test();
      final now = DateTime.now().toUtc();
      await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: 'n-dispose',
          userId: 'test-user',
          content: '',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final mgr = YjsSyncManager(db: db, userId: 'test-user');
      final doc = await mgr.loadDoc('n-dispose');

      // === Replicate note_editor_provider.dart lifecycle verbatim ===
      final controller = NoteEditorController(userId: 'test-user');
      controller.bind('n-dispose');

      Timer? flushDebounce;
      Future<void>? flushChain;
      bool wasLocallyEdited = false;

      Future<void> doFlush() async {
        flushDebounce?.cancel();
        flushDebounce = null;
        final prev = flushChain ?? Future.value();
        flushChain = prev.then((_) async {
          await mgr.projectNodes('n-dispose', markDirty: wasLocallyEdited);
          wasLocallyEdited = false;
          await mgr.persist('n-dispose');
        });
        await flushChain;
      }

      void scheduleFlush() {
        flushDebounce?.cancel();
        flushDebounce = Timer(
          const Duration(milliseconds: 500),
          () { unawaited(doFlush()); },
        );
      }

      controller.initFromDoc(
        doc: doc,
        noteId: 'n-dispose',
        onDocChanged: ({required isRemote}) {
          if (!isRemote) { wasLocallyEdited = true; }
          scheduleFlush();
        },
        onDocCommitted: (_) { scheduleFlush(); },
      );

      // Edit via the controller/bridge (not raw YDoc ops).
      // This triggers onDocChanged → wasLocallyEdited + 500ms debounce.
      controller.editor!.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: 0,
          newNode: ParagraphNode(
            id: 'p1',
            text: AttributedText('typed before navigate'),
          ),
        ),
      ]);

      // Let coordinator's 50ms debounce + bridge flush + onDocChanged fire.
      await Future.delayed(const Duration(milliseconds: 100));

      expect(wasLocallyEdited, isTrue,
        reason: 'Edit must propagate through bridge before dispose');

      // "Dispose" before the 500ms debounce fires.
      final disposeStart = DateTime.now();
      flushDebounce?.cancel();
      await controller.dispose().then((_) async {
        await doFlush();
      });
      final elapsed = DateTime.now().difference(disposeStart);
      expect(elapsed.inMilliseconds, lessThan(500),
        reason: 'Dispose flush must not wait for the 500ms timer');

      // Verify snapshot: Yjs state was persisted.
      final persisted = await (db.select(db.localYjsStates)
        ..where((t) => t.noteId.equals('n-dispose'))).getSingleOrNull();
      expect(persisted, isNotNull);

      // Verify Yjs content survives reload.
      final mgr2 = YjsSyncManager(db: db, userId: 'test-user');
      final doc2 = await mgr2.loadDoc('n-dispose');
      expect(doc2.getText('content/p1')!.toString(), 'typed before navigate',
        reason: 'Yjs content must survive persist + reload');

      // Verify relational projection was updated.
      final note = await db.notesDao.getNoteById('n-dispose');
      expect(note, isNotNull);
      expect(note!.content, contains('typed before navigate'),
        reason: 'Relational projection must be updated on dispose');

      await db.close();
    });
  });

  group('Sync regression — two-device CRDT convergence', () {
    test('independent edits on different paragraphs converge on reopen',
        () async {
      final dbA = AppDatabase.test(executor: NativeDatabase.memory());
      final dbB = AppDatabase.test(executor: NativeDatabase.memory());
      final now = DateTime.now().toUtc();

      // Insert same note in both databases.
      for (final db in [dbA, dbB]) {
        await db.into(db.notes).insert(
          NotesCompanion.insert(
            id: 'n-converge',
            userId: 'u-1',
            content: '',
            createdAt: now,
            updatedAt: now,
            isDirty: const Value(false),
            hasRemoteCopy: const Value(true),
          ),
        );
      }

      final mgrA = YjsSyncManager(db: dbA, userId: 'u-1');
      final mgrB = YjsSyncManager(db: dbB, userId: 'u-1');

      // Device A: create initial doc with two paragraphs.
      final docA = await mgrA.loadDoc('n-converge');
      seedDocWithParagraphs(docA, [
        {'id': 'p1', 'position': 'a0', 'text': 'Hello from A'},
        {'id': 'p2', 'position': 'b0', 'text': 'Second line'},
      ]);
      final initState = encodeStateAsUpdate(docA);
      await dbA.into(dbA.localYjsStates).insertOnConflictUpdate(
        LocalYjsStatesCompanion(
          noteId: const Value('n-converge'),
          state: Value(initState),
          updatedAt: Value(now),
        ),
      );

      // Device B: apply the same initial state.
      final docB = Doc();
      applyUpdate(docB, initState);
      // We inject the binary state via a fresh mgrB load by writing it.
      await dbB.into(dbB.localYjsStates).insertOnConflictUpdate(
        LocalYjsStatesCompanion(
          noteId: const Value('n-converge'),
          state: Value(initState),
          updatedAt: Value(now),
        ),
      );

      // Device A edits p1.
      await mgrA.loadDoc('n-converge');
      final da = await mgrA.loadDoc('n-converge');
      da.transact((txn) {
        da.getText('content/p1')!.delete(0, da.getText('content/p1')!.length);
        da.getText('content/p1')!.insert(0, 'A edits p1');
        da.getMap<Object>('nodes')!.set(
          'p1',
          '{"id":"p1","position":"a0","type":"paragraph","data":{"text":"A edits p1"}}',
        );
      });
      final updateA = encodeStateAsUpdate(da);

      // Device B edits p2.
      await mgrB.loadDoc('n-converge');
      final dbDoc = await mgrB.loadDoc('n-converge');
      dbDoc.transact((txn) {
        dbDoc.getText('content/p2')!.delete(0, dbDoc.getText('content/p2')!.length);
        dbDoc.getText('content/p2')!.insert(0, 'B edits p2');
        dbDoc.getMap<Object>('nodes')!.set(
          'p2',
          '{"id":"p2","position":"b0","type":"paragraph","data":{"text":"B edits p2"}}',
        );
      });
      final updateB = encodeStateAsUpdate(dbDoc);

      // Sync: A receives B's update.
      applyUpdate(da, updateB);
      await mgrA.persist('n-converge');

      // Sync: B receives A's update.
      final docB2 = await mgrB.loadDoc('n-converge');
      applyUpdate(docB2, updateA);
      await mgrB.persist('n-converge');

      // Validate convergence: both docs have both edits.
      expect(
        da.getText('content/p1')!.toString(),
        'A edits p1',
        reason: 'Device A must have its own edit on p1',
      );
      expect(
        da.getText('content/p2')!.toString(),
        'B edits p2',
        reason: 'Device A must have B edit on p2 after sync',
      );
      expect(
        docB2.getText('content/p1')!.toString(),
        'A edits p1',
        reason: 'Device B must have A edit on p1 after sync',
      );
      expect(
        docB2.getText('content/p2')!.toString(),
        'B edits p2',
        reason: 'Device B must have its own edit on p2',
      );

      // Reopen on both devices: state must survive persist+reload.
      final mgrA2 = YjsSyncManager(db: dbA, userId: 'u-1');
      final reloadA = await mgrA2.loadDoc('n-converge');
      expect(reloadA.getText('content/p1')!.toString(), 'A edits p1');
      expect(reloadA.getText('content/p2')!.toString(), 'B edits p2');

      final mgrB2 = YjsSyncManager(db: dbB, userId: 'u-1');
      final reloadB = await mgrB2.loadDoc('n-converge');
      expect(reloadB.getText('content/p1')!.toString(), 'A edits p1');
      expect(reloadB.getText('content/p2')!.toString(), 'B edits p2');

      await dbA.close();
      await dbB.close();
    });
  });

  group('Sync regression — reorder blocks persist through lifecycle', () {
    test('reorder survives persist + reload', () async {
      final db = AppDatabase.test(executor: NativeDatabase.memory());
      final now = DateTime.now().toUtc();
      await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: 'n-reorder',
          userId: 'u-1',
          content: '',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ),
      );

      final mgr = YjsSyncManager(db: db, userId: 'u-1');
      final doc = await mgr.loadDoc('n-reorder');

      // Create three nodes in order: A, B, C.
      seedDocWithParagraphs(doc, [
        {'id': 'a', 'position': 'a0', 'text': 'Node A'},
        {'id': 'b', 'position': 'b0', 'text': 'Node B'},
        {'id': 'c', 'position': 'c0', 'text': 'Node C'},
      ]);

      // Reorder locally: move C to first position.
      doc.transact((txn) {
        final nodesMap = doc.getMap<Object>('nodes')!;
        final rawC = nodesMap.get('c');
        if (rawC is String) {
          final data = jsonDecode(rawC) as Map<String, dynamic>;
          data['position'] = 'a-1';
          nodesMap.set('c', jsonEncode(data));
        }
        final rawA = nodesMap.get('a');
        if (rawA is String) {
          final data = jsonDecode(rawA) as Map<String, dynamic>;
          data['position'] = 'b0';
          nodesMap.set('a', jsonEncode(data));
        }
      });

      var afterReorder = noteNodesFromDoc(doc);
      expect(afterReorder.map((n) => n.id).toList(), ['c', 'a', 'b']);

      // Persist + reload.
      await mgr.persist('n-reorder');
      final mgr2 = YjsSyncManager(db: db, userId: 'u-1');
      final reloaded = await mgr2.loadDoc('n-reorder');

      var afterReload = noteNodesFromDoc(reloaded);
      expect(
        afterReload.map((n) => n.id).toList(),
        ['c', 'a', 'b'],
        reason: 'Reorder must survive persist + reload',
      );

      await db.close();
    });
  });

  group('Sync regression — partial remote update applies correctly', () {
    test('remote merge via mergeRemoteStatesAndProject updates single node',
        () async {
      final db = AppDatabase.test(executor: NativeDatabase.memory());
      final now = DateTime.now().toUtc();
      await db.into(db.notes).insert(
        NotesCompanion.insert(
          id: 'n-patch',
          userId: 'u-1',
          content: '',
          createdAt: now,
          updatedAt: now,
          isDirty: const Value(false),
          hasRemoteCopy: const Value(true),
        ),
      );

      // Seed initial Yjs state (local doc + snapshot).
      final mgr = YjsSyncManager(db: db, userId: 'u-1');
      final doc = await mgr.loadDoc('n-patch');
      seedDocWithParagraphs(doc, [
        {'id': 'a', 'position': 'a0', 'text': 'Paragraph A'},
        {'id': 'b', 'position': 'b0', 'text': 'Paragraph B'},
        {'id': 'c', 'position': 'c0', 'text': 'Paragraph C'},
      ]);
      await mgr.persist('n-patch');

      // Build a remote Yjs state that contains only B's update.
      final stateBytes = encodeStateAsUpdate(doc);
      final remoteUpdate = Doc();
      applyUpdate(remoteUpdate, stateBytes);
      remoteUpdate.transact((txn) {
        remoteUpdate.getMap<Object>('nodes')!.set(
          'b',
          '{"id":"b","position":"b0","type":"paragraph","data":{"text":"Paragraph B updated by server"}}',
        );
      });
      final remoteStateBytes = encodeStateAsUpdate(remoteUpdate);

      // Process via the app's actual remote merge path.
      // Note: this only processes non-active notes (background sync).
      await mgr.mergeRemoteStatesAndProject(
        rawYjsStates: [
          {
            'note_id': 'n-patch',
            'state': remoteStateBytes.toList(),
            'updated_at': now.toUtc().toIso8601String(),
          },
        ],
        isActiveNote: (_) => false,
        onMerged: (_) {},
      );

      // Reload doc from DB
      mgr.evictDoc('n-patch');
      final reloaded = await mgr.loadDoc('n-patch');

      // Node A and C must be untouched in the nodes map.
      final rawA = reloaded.getMap<Object>('nodes')!.get('a') as String;
      final rawC = reloaded.getMap<Object>('nodes')!.get('c') as String;
      expect(rawA, contains('Paragraph A'));
      expect(rawC, contains('Paragraph C'));

      // Node B must reflect the remote update.
      final rawB = reloaded.getMap<Object>('nodes')!.get('b') as String;
      expect(rawB, contains('Paragraph B updated by server'));

      // All three nodes present in sorted projection.
      final nodes = noteNodesFromDoc(reloaded);
      expect(nodes, hasLength(3));
      expect(nodes.map((n) => n.id).toList(), ['a', 'b', 'c']);

      await db.close();
    });
  });
}
