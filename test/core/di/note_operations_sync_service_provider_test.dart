import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/sync/note_operations_sync_service.dart';
import 'package:supanotes/features/notes/data/note_sync_client.dart';

final _testUserIdProvider = StateProvider<String?>((ref) => 'user-a');

class _MockNoteSyncClient extends Mock implements NoteSyncClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.test();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        noteSyncClientProvider.overrideWithValue(_MockNoteSyncClient()),
        currentUserIdProvider.overrideWith((ref) {
          return ref.watch(_testUserIdProvider);
        }),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('service is created only when there is an authenticated user', () {
    final service = container.read(noteOperationsSyncServiceProvider);
    expect(service, isA<NoteOperationsSyncService>());

    container.read(_testUserIdProvider.notifier).state = null;

    expect(
      () => container.read(noteOperationsSyncServiceProvider),
      throwsA(
        predicate((error) => error.toString().contains('authenticated user')),
      ),
    );
  });

  test('service instance stays stable during one authenticated session', () {
    final first = container.read(noteOperationsSyncServiceProvider);
    final second = container.read(noteOperationsSyncServiceProvider);

    expect(identical(first, second), isTrue);
  });

  test('two notes use the same service with independent queues', () async {
    final service = container.read(noteOperationsSyncServiceProvider);
    final releaseNoteA = Completer<void>();
    var noteAEntered = false;
    var noteBCompleted = false;

    final noteAFuture = service.runSerialized('note-a', () async {
      noteAEntered = true;
      await releaseNoteA.future;
      return 'a';
    });
    await pumpEventQueue();

    final noteBFuture = service.runSerialized('note-b', () async {
      noteBCompleted = true;
      return 'b';
    });

    expect(await noteBFuture, 'b');
    expect(noteAEntered, isTrue);
    expect(noteBCompleted, isTrue);

    releaseNoteA.complete();
    expect(await noteAFuture, 'a');
    expect(
      identical(service, container.read(noteOperationsSyncServiceProvider)),
      isTrue,
    );
  });

  test(
    'same note calls from different reads use the same serialized queue',
    () async {
      final firstConsumer = container.read(noteOperationsSyncServiceProvider);
      final secondConsumer = container.read(noteOperationsSyncServiceProvider);
      final releaseFirst = Completer<void>();
      final order = <String>[];

      final first = firstConsumer.runSerialized('note-one', () async {
        order.add('first-start');
        await releaseFirst.future;
        order.add('first-end');
      });
      await pumpEventQueue();

      final second = secondConsumer.runSerialized('note-one', () async {
        order.add('second');
      });
      await pumpEventQueue();

      expect(order, ['first-start']);
      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(order, ['first-start', 'first-end', 'second']);
    },
  );

  test('logout invalidates the provider for new work', () {
    final authenticated = container.read(noteOperationsSyncServiceProvider);

    container.read(_testUserIdProvider.notifier).state = null;

    expect(
      () => container.read(noteOperationsSyncServiceProvider),
      throwsA(
        predicate((error) => error.toString().contains('authenticated user')),
      ),
    );
    expect(authenticated, isA<NoteOperationsSyncService>());
  });

  test(
    'account switch creates a new service after invalidating the old scope',
    () {
      final userAService = container.read(noteOperationsSyncServiceProvider);

      container.read(_testUserIdProvider.notifier).state = 'user-b';

      final userBService = container.read(noteOperationsSyncServiceProvider);
      expect(identical(userAService, userBService), isFalse);
      expect(userBService.clientId, userAService.clientId);
    },
  );

  test('persisted outbox remains available after service recreation', () async {
    final serviceA = container.read(noteOperationsSyncServiceProvider);
    await serviceA.enqueueOperation(
      'note-outbox',
      OperationRequest(
        operationId: 'op-persisted',
        baseRevision: 1,
        kind: 'text_delta',
        blockId: 'b1',
        payload: const {
          'delta': [
            {'insert': 'local'},
          ],
        },
      ),
    );

    container.read(_testUserIdProvider.notifier).state = 'user-b';
    final serviceB = container.read(noteOperationsSyncServiceProvider);
    final pending = await serviceB.getPendingOperations('note-outbox');

    expect(identical(serviceA, serviceB), isFalse);
    expect(pending, hasLength(1));
    expect(pending.single.operationId, 'op-persisted');
    expect(pending.single.status, 'pending');
  });

  test(
    'provider keeps long-lived REST OT dependencies outside autoDispose scope',
    () {
      final dao = container.read(noteOperationsDaoProvider);
      final service = container.read(noteOperationsSyncServiceProvider);

      expect(dao, same(container.read(noteOperationsDaoProvider)));
      expect(service, same(container.read(noteOperationsSyncServiceProvider)));
    },
  );
}
