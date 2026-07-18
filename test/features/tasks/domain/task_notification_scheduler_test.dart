import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supanotes/core/database/database.dart';
import 'package:supanotes/core/di/providers.dart';
import 'package:supanotes/core/notifications/local_notification_service.dart';
import 'package:supanotes/features/tasks/data/local/tasks_local_repository.dart';
import 'package:supanotes/features/tasks/domain/task_notification_scheduler.dart';
import 'package:timezone/data/latest.dart' as tzData;
import 'package:timezone/timezone.dart' as tz;

class FakeFlutterLocalNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  int initializedCount = 0;
  List<Map<String, dynamic>> schedules = [];
  List<int> cancelled = [];
  bool cancelAllCalled = false;

  @override
  Future<void> cancelAll() async {
    cancelAllCalled = true;
  }

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializedCount++;
    return true;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    schedules.add({
      'id': id,
      'title': title,
      'body': body,
      'scheduledDate': scheduledDate,
    });
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelled.add(id);
  }
}

class MockTasksLocalRepository extends Mock implements TasksLocalRepository {}

void main() {
  late FakeFlutterLocalNotificationsPlugin fakePlugin;
  late MockTasksLocalRepository mockTasksRepo;
  late ProviderContainer container;

  setUp(() {
    tzData.initializeTimeZones();
    fakePlugin = FakeFlutterLocalNotificationsPlugin();
    mockTasksRepo = MockTasksLocalRepository();

    container = ProviderContainer(
      overrides: [
        localNotificationServiceProvider.overrideWithValue(
          LocalNotificationService(plugin: fakePlugin),
        ),
        tasksLocalRepositoryProvider.overrideWithValue(mockTasksRepo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('schedules notifications for tasks with due date', () async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    
    final openTasks = [
      TaskData(
        id: 'task-1',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Has Time',
        status: 'open',
        position: '1',
        createdAt: now,
        updatedAt: now,
        hasTime: true,
        dueDate: tomorrow,
      ),
      TaskData(
        id: 'task-2',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'No Time',
        status: 'open',
        position: '2',
        createdAt: now,
        updatedAt: now,
        hasTime: false,
        dueDate: tomorrow,
      ),
      TaskData(
        id: 'task-3',
        userId: 'user-1',
        noteId: 'note-1',
        title: 'Past Task',
        status: 'open',
        position: '3',
        createdAt: now,
        updatedAt: now,
        hasTime: true,
        dueDate: now.subtract(const Duration(days: 1)),
      ),
    ];
    
    when(() => mockTasksRepo.watchOpenTasks())
        .thenAnswer((_) => Stream.value(openTasks));
        
    // Listen to scheduler to keep it alive
    final sub = container.listen(taskNotificationSchedulerProvider, (_, __) {});
    
    // Wait for async stream handling
    await Future.delayed(const Duration(milliseconds: 200));
    
    expect(fakePlugin.initializedCount, greaterThan(0));
    expect(fakePlugin.schedules, hasLength(2));
    
    // Task 1: Has time, should schedule at the exact time
    final schedule1 = fakePlugin.schedules.firstWhere((s) => s['id'] == 'task-1'.hashCode);
    expect(schedule1['title'], 'Has Time');
    expect(
      schedule1['scheduledDate'],
      predicate((tz.TZDateTime d) => d.isAtSameMomentAs(tomorrow))
    );
    
    // Task 2: No time, should schedule at 9:00 AM
    final schedule2 = fakePlugin.schedules.firstWhere((s) => s['id'] == 'task-2'.hashCode);
    expect(schedule2['title'], 'No Time');
    expect(
      schedule2['scheduledDate'],
      predicate((tz.TZDateTime d) => d.isAtSameMomentAs(DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0)))
    );
    
    // Task 3 should not be scheduled
    final hasTask3 = fakePlugin.schedules.any((s) => s['id'] == 'task-3'.hashCode);
    expect(hasTask3, isFalse);
    
    sub.close();
  });
  
  test('cancels notifications when a task is no longer open', () async {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    
    final task1 = TaskData(
      id: 'task-1',
      userId: 'user-1',
      noteId: 'note-1',
      title: 'Has Time',
      status: 'open',
      position: '1',
      createdAt: now,
      updatedAt: now,
      hasTime: true,
      dueDate: tomorrow,
    );
    
    when(() => mockTasksRepo.watchOpenTasks())
        .thenAnswer((_) => Stream.fromIterable([
              [task1],
              <TaskData>[], 
            ]));
            
    final sub = container.listen(taskNotificationSchedulerProvider, (_, __) {});
    
    await Future.delayed(const Duration(milliseconds: 200));
    
    expect(fakePlugin.schedules, hasLength(1));
    expect(fakePlugin.cancelled, contains('task-1'.hashCode));
    
    sub.close();
  });
}
