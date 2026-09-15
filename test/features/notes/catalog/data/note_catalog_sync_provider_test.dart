import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/note_remote_sync_runtime.dart';
import 'package:supanotes/core/sync/sync_feed_client.dart';
import 'package:supanotes/core/sync/task_outbox_worker.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/notes/editor/sync/note_sync_client.dart';

class _StubAuthController extends AuthController {
  @override
  Future<User?> build() async =>
      const User(id: 'user-1', email: 'user@example.com', name: 'User');
}

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('incremental runtime bootstraps a remote note once', () async {
    final database = AppDatabase.test();
    final client = _MockNoteSyncClient();
    final lifecycle = <String>[];
    final connectivity = StreamController<List<ConnectivityResult>>.broadcast();
    final resumedFeed = Completer<void>();
    var holdNextTaskDrain = false;
    Completer<void>? releaseTaskDrain;
    final taskWorker = TaskOutboxWorker(
      loadPendingTaskIds: () async {
        lifecycle.add('task-drain');
        if (holdNextTaskDrain) {
          holdNextTaskDrain = false;
          final release = releaseTaskDrain;
          if (release != null) await release.future;
        }
        return const [];
      },
      syncTask: (_) async {},
    );
    final feedCalls = <int>[];
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        noteSyncClientProvider.overrideWithValue(client),
        taskOutboxWorkerProvider.overrideWithValue(taskWorker),
        taskSyncServiceProvider.overrideWithValue(null),
        authControllerProvider.overrideWith(_StubAuthController.new),
        noteOutboxConnectivityChangesProvider.overrideWithValue(
          connectivity.stream,
        ),
        syncChangesFetcherProvider.overrideWithValue(({
          required int after,
          required int limit,
          SyncFeedScope scope = SyncFeedScope.notes,
        }) async {
          lifecycle.add('feed');
          feedCalls.add(after);
          if (feedCalls.length > 2 && !resumedFeed.isCompleted) {
            resumedFeed.complete();
          }
          return SyncChangePage(
            cursor: after,
            watermark: 0,
            hasMore: false,
            changes: const [],
          );
        }),
        remoteNoteMetadataLoaderProvider.overrideWithValue((_) async {
          throw StateError('incremental metadata loader should not run');
        }),
      ],
    );
    final completed = Completer<void>();

    addTearDown(() async {
      container.dispose();
      await taskWorker.dispose();
      await connectivity.close();
      await database.close();
    });

    when(client.listNotes).thenAnswer(
      (_) async {
        lifecycle.add('notes');
        return [
          {
            'id': 'remote-note',
            'user_id': 'user-1',
            'created_at': '2026-08-01T12:00:00.000Z',
            'updated_at': '2026-08-01T12:00:00.000Z',
            'collapse_images': false,
          },
        ];
      },
    );
    when(() => client.getDocument('remote-note')).thenAnswer(
      (_) async => NoteDocumentResponse(
        noteId: 'remote-note',
        revision: 1,
        document: const {'schemaVersion': 1, 'blocks': []},
        serverTime: DateTime.utc(2026, 8, 1, 12),
      ),
    );

    final subscription = container.listen(noteRemoteSyncRuntimeProvider, (
      _,
      next,
    ) {
      if (next.hasError && !completed.isCompleted) {
        completed.completeError(
          next.error!,
          next.stackTrace ?? StackTrace.current,
        );
      } else if (next.hasValue && !completed.isCompleted) {
        completed.complete();
      }
    });
    addTearDown(subscription.close);

    await completed.future.timeout(const Duration(seconds: 2));

    final note = await database.notesDao.getNoteById('remote-note');
    expect(note, isNotNull);
    expect(note!.userId, 'user-1');
    expect(note.hasRemoteCopy, isTrue);
    expect(feedCalls, [0, 0]);
    expect(
      lifecycle.indexOf('task-drain'),
      lessThan(lifecycle.indexOf('notes')),
    );
    expect(
      lifecycle.indexOf('task-drain'),
      lessThan(lifecycle.indexOf('feed')),
    );
    verify(client.listNotes).called(1);
    verify(() => client.getDocument('remote-note')).called(1);

    lifecycle.clear();
    releaseTaskDrain = Completer<void>();
    holdNextTaskDrain = true;
    connectivity.add([ConnectivityResult.wifi]);
    await pumpEventQueue();
    expect(resumedFeed.isCompleted, isFalse);

    releaseTaskDrain?.complete();
    await resumedFeed.future.timeout(const Duration(seconds: 2));
    expect(
      lifecycle.indexOf('task-drain'),
      lessThan(lifecycle.indexOf('feed')),
    );
  });
}
