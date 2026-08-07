import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_editor/super_editor.dart';

import 'package:supanotes/main.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';
import 'package:supanotes/features/notes/editor/sync/note_operation_adapter.dart';

class _OfflineClient extends Mock implements NoteSyncClient {}

class _UnauthenticatedAuthController extends AuthController {
  @override
  Future<User?> build() async => null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      SyncRequest(knownRevision: 0, operations: const [], clientId: 'fallback'),
    );
  });

  group('REST/OT persistence on a device', () {
    testWidgets('the real app boots into the unauthenticated route', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authControllerProvider.overrideWith(
            _UnauthenticatedAuthController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SupaNotesApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SupaNotesApp), findsOneWidget);
    });

    testWidgets('offline edit survives a cold restart before sync', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox(width: 1, height: 1));
      final database = AppDatabase.test();
      addTearDown(database.close);
      final service = NoteOperationsSyncService(
        syncClient: _OfflineClient(),
        dao: database.noteOperationsDao,
        clientId: 'device-client',
        actorId: 'user-device',
      );

      final firstDocument = _emptyDocument();
      final firstEditor = createDefaultDocumentEditor(
        document: firstDocument,
        composer: MutableDocumentComposer(),
      );
      final firstAdapter = NoteOperationAdapter(
        document: firstDocument,
        syncService: service,
        noteId: 'device-offline-note',
        editor: firstEditor,
      );
      await firstAdapter.start();
      firstEditor.execute([
        InsertTextRequest(
          documentPosition: const DocumentPosition(
            nodeId: 'init',
            nodePosition: TextNodePosition(offset: 0),
          ),
          textToInsert: 'persistido no dispositivo',
          attributions: const {},
        ),
      ]);
      await firstAdapter.flushNow();
      firstAdapter.dispose();

      final restartedDocument = _emptyDocument();
      final restartedEditor = createDefaultDocumentEditor(
        document: restartedDocument,
        composer: MutableDocumentComposer(),
      );
      final restartedAdapter = NoteOperationAdapter(
        document: restartedDocument,
        syncService: service,
        noteId: 'device-offline-note',
        editor: restartedEditor,
      );
      addTearDown(restartedAdapter.dispose);
      await restartedAdapter.start();

      expect(
        (restartedDocument.first as TextNode).text.toPlainText(),
        'persistido no dispositivo',
      );
      expect(
        await database.noteOperationsDao.getPendingOperations(
          'device-offline-note',
          ownerUserId: 'user-device',
        ),
        hasLength(1),
      );
    });

    testWidgets(
      'process death during a weak connection keeps in-flight edits',
      (tester) async {
        await tester.pumpWidget(const SizedBox(width: 1, height: 1));
        final database = AppDatabase.test();
        addTearDown(database.close);
        final client = _OfflineClient();
        when(
          () => client.syncOperations(any(), any()),
        ).thenThrow(StateError('connection interrupted'));
        final service = NoteOperationsSyncService(
          syncClient: client,
          dao: database.noteOperationsDao,
          clientId: 'device-client',
          actorId: 'user-device',
        );

        final document = _emptyDocument();
        final editor = createDefaultDocumentEditor(
          document: document,
          composer: MutableDocumentComposer(),
        );
        final adapter = NoteOperationAdapter(
          document: document,
          syncService: service,
          noteId: 'device-in-flight-note',
          editor: editor,
        );
        await adapter.start();
        editor.execute([
          InsertTextRequest(
            documentPosition: const DocumentPosition(
              nodeId: 'init',
              nodePosition: TextNodePosition(offset: 0),
            ),
            textToInsert: 'não perder esta edição',
            attributions: const {},
          ),
        ]);
        await adapter.flushNow();
        await expectLater(
          service.syncPending('device-in-flight-note'),
          throwsA(isA<StateError>()),
        );
        adapter.dispose();

        final restartedDocument = _emptyDocument();
        final restartedEditor = createDefaultDocumentEditor(
          document: restartedDocument,
          composer: MutableDocumentComposer(),
        );
        final restartedAdapter = NoteOperationAdapter(
          document: restartedDocument,
          syncService: service,
          noteId: 'device-in-flight-note',
          editor: restartedEditor,
        );
        addTearDown(restartedAdapter.dispose);
        await restartedAdapter.start();

        expect(
          (restartedDocument.first as TextNode).text.toPlainText(),
          'não perder esta edição',
        );
      },
    );

    testWidgets(
      'a second account cannot project or take over another account session',
      (tester) async {
        await tester.pumpWidget(const SizedBox(width: 1, height: 1));
        final database = AppDatabase.test();
        addTearDown(database.close);
        await database.noteOperationsDao.insertPendingOperation(
          PendingNoteOperationsCompanion.insert(
            operationId: 'account-a-operation',
            noteId: 'shared-account-note',
            ownerUserId: const Value('account-a'),
            baseRevision: 0,
            ordinal: 0,
            kind: 'text_delta',
            blockId: const Value('init'),
            payloadJson: '{"ops":[{"insert":"account-a"}]}',
            createdAt: DateTime.utc(2026, 8, 3),
          ),
        );
        await database.noteOperationsDao.upsertSyncSession(
          SyncSessionsCompanion.insert(
            noteId: 'shared-account-note',
            ownerUserId: const Value('account-a'),
            knownRevision: 0,
            operationIds: '["account-a-operation"]',
            startedAt: DateTime.utc(2026, 8, 3).toIso8601String(),
          ),
        );

        final clientB = _OfflineClient();
        final serviceB = NoteOperationsSyncService(
          syncClient: clientB,
          dao: database.noteOperationsDao,
          clientId: 'device-b',
          actorId: 'account-b',
        );

        expect(
          await serviceB.loadPendingProjection('shared-account-note'),
          isEmpty,
        );
        final result = await serviceB.syncPending('shared-account-note');
        expect(result.blockedReason, 'foreign_sync_session');
        verifyNever(() => clientB.syncOperations(any(), any()));
      },
    );
  });
}

MutableDocument _emptyDocument() => MutableDocument(
  nodes: [ParagraphNode(id: 'init', text: AttributedText())],
);
