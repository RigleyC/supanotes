import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supanotes/core/auth/current_user.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/notifications/local_notification_service.dart';
import 'package:supanotes/features/auth/domain/user.dart';
import 'package:supanotes/features/auth/presentation/controllers/auth_controller.dart';
import 'package:supanotes/features/tasks/domain/task_notification_entry.dart';
import 'package:supanotes/features/tasks/domain/task_notification_id.dart';
import 'package:supanotes/features/tasks/domain/note_task_notification_source.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:supanotes/features/tasks/domain/task_notification_source.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('merges notification sources without using the list filter', () async {
    final first = _FakeSource([
      _entry('same-id', TaskNotificationEntrySource.standalone),
    ]);
    final second = _FakeSource([
      _entry('same-id', TaskNotificationEntrySource.note, noteId: 'note-1'),
    ]);

    final entries = await CombinedTaskNotificationSource([
      first,
      second,
    ]).readOpenTasks('user-1');

    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry.sourceKey), {
      'task:same-id',
      'note:note-1:same-id',
    });
    expect(first.requestedUserId, 'user-1');
    expect(second.requestedUserId, 'user-1');
  });

  test('standalone reader applies occurrence and tombstone policy', () async {
    final database = AppDatabase.test();
    addTearDown(database.close);
    final now = DateTime(2026, 9, 15, 10);
    await database.tasksDao.insertOrUpdateTask(
      TasksCompanion.insert(
        id: 'open',
        ownerUserId: 'user-1',
        title: 'Open',
        dueDate: Value(DateTime(2026, 9, 16, 9)),
        hasTime: const Value(true),
        reminder: const Value('at_time'),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await database.tasksDao.insertOrUpdateTask(
      TasksCompanion.insert(
        id: 'done',
        ownerUserId: 'user-1',
        title: 'Done',
        isCompleted: const Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await database.tasksDao.insertOrUpdateTask(
      TasksCompanion.insert(
        id: 'deleted',
        ownerUserId: 'user-1',
        title: 'Deleted',
        deletedAt: Value(now),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final entries = await StandaloneTaskNotificationSource(
      database.tasksDao,
      clock: () => now,
    ).readOpenTasks('user-1');

    expect(entries.map((entry) => entry.id), ['open']);
    expect(entries.single.source, TaskNotificationEntrySource.standalone);
    expect(entries.single.dueDate, DateTime(2026, 9, 16, 9));
  });

  test(
    'cancels the persisted legacy ID before scheduling the new ID',
    () async {
      final scheduledAt = DateTime.now().add(const Duration(days: 2));
      final legacyCacheKey = 'task_notification_schedule_cache_user-1';
      SharedPreferences.setMockInitialValues({
        legacyCacheKey: jsonEncode({
          'task-1': scheduledAt.toIso8601String(),
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final service = _RecordingNotificationService();
      final database = AppDatabase.test();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(database),
          currentUserIdProvider.overrideWithValue('user-1'),
          authControllerProvider.overrideWith(() => _AuthController()),
          localNotificationServiceProvider.overrideWithValue(service),
          standaloneTaskNotificationSourceProvider.overrideWith(
            (ref) => const Stream<List<TaskNotificationEntry>>.empty(),
          ),
          noteTaskNotificationSourceProvider.overrideWith(
            (ref) => const Stream<List<TaskNotificationEntry>>.empty(),
          ),
        ],
      );
      await container.read(authControllerProvider.future);
      final schedulerSubscription = container.listen(
        taskNotificationSchedulerProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(() async {
        schedulerSubscription.close();
        container.dispose();
        await database.close();
      });

      final scheduler = container.read(
        taskNotificationSchedulerProvider.notifier,
      );
      await container.read(taskNotificationSchedulerProvider.future);
      final entry = TaskNotificationEntry(
        id: 'task-1',
        title: 'Task',
        dueDate: scheduledAt,
        hasTime: true,
        reminder: 'at_time',
        source: TaskNotificationEntrySource.standalone,
      );
      await scheduler.reconcile(tasks: [entry]);

      final legacyId = TaskNotificationId.legacyForTask('user-1', 'task-1');
      final newId = TaskNotificationId.forTask(
        userId: 'user-1',
        taskId: 'task-1',
        scheduledAt: scheduledAt,
      );
      expect(
        service.cancelled,
        contains(legacyId),
        reason: service.events.toString(),
      );
      expect(
        service.scheduled,
        contains(newId),
        reason: service.events.toString(),
      );
      expect(
        service.events.indexOf('cancel:$legacyId'),
        lessThan(service.events.indexOf('schedule:$newId')),
      );
    },
  );
}

TaskNotificationEntry _entry(
  String id,
  TaskNotificationEntrySource source, {
  String? noteId,
}) => TaskNotificationEntry(
  id: id,
  title: id,
  dueDate: DateTime(2026, 9, 15, 9),
  hasTime: true,
  reminder: 'at_time',
  source: source,
  noteId: noteId,
);

class _FakeSource implements TaskNotificationSource {
  _FakeSource(this.entries);

  final List<TaskNotificationEntry> entries;
  String? requestedUserId;

  @override
  Future<List<TaskNotificationEntry>> readOpenTasks(String userId) async {
    requestedUserId = userId;
    return entries;
  }
}

class _AuthController extends AuthController {
  @override
  Future<User?> build() async => const User(
    id: 'user-1',
    email: 'user@example.com',
    name: 'User',
  );
}

class _RecordingNotificationService extends LocalNotificationService {
  _RecordingNotificationService() : super(supportedPlatform: false);

  final cancelled = <int>[];
  final scheduled = <int>[];
  final events = <String>[];

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    events.add('cancel:$id');
  }

  @override
  Future<void> scheduleTaskNotification(
    int notificationId,
    String title,
    String body,
    DateTime date,
  ) async {
    scheduled.add(notificationId);
    events.add('schedule:$notificationId');
  }
}
