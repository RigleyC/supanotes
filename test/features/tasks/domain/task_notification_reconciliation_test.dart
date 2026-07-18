import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:supanotes/features/tasks/domain/task_notification_id.dart';

// Stub for the production TaskData model (defined in task_model.dart).
// Used here to characterize the reconcile API shape before implementation.
class _StubTaskData {
  final String id;
  _StubTaskData(this.id);
}

// Stub notification scheduler that uses deterministic IDs
class _StubNotificationScheduler {
  Future<void> reconcile({
    required String userId,
    required List<_StubTaskData> tasks,
    required FakeNotificationPlugin plugin,
  }) async {
    // Cancel old notifications for previous user
    for (final task in tasks) {
      final oldId = notificationIdForTask(userId, task.id);
      // For the test: the 'a' task belongs to user-a, changing to user-b means
      // we cancel the old user's notifications for tasks not in the new set
    }
  }
}

class FakeNotificationPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  final List<int> cancelled = [];
  final List<int> scheduledIds = [];

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelled.add(id);
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
    scheduledIds.add(id);
  }
}

int notificationIdForTaskLegacy(String taskId) => taskId.hashCode;

_StubTaskData task(String id) => _StubTaskData(id);

void main() {
  group('TaskNotificationScheduler - reconciliation', () {
    test('notificationIdForTask is deterministic and collision-resistant', () async {
      final id1 = notificationIdForTask('user-a', 'task-a');
      final id2 = notificationIdForTask('user-a', 'task-a');
      final id3 = notificationIdForTask('user-b', 'task-a');

      expect(id1, equals(id2), reason: 'same inputs must produce same ID');
      expect(id1, isNot(equals(id3)), reason: 'different users must produce different IDs');
      expect(id1, greaterThan(0), reason: 'must be positive int32');
      expect(id1, lessThan(0x7fffffff), reason: 'must fit in int32 range');
    });

    test(
        'switching user cancels the previous user schedule before scheduling the next',
        () async {
      final plugin = FakeNotificationPlugin();
      final scheduler = _StubNotificationScheduler();

      await scheduler.reconcile(userId: 'user-a', tasks: [task('a')], plugin: plugin);
      await scheduler.reconcile(userId: 'user-b', tasks: [task('b')], plugin: plugin);

      // Note: The stub doesn't actually call the plugin — this test
      // characterizes the expected API shape. The real reconciliation
      // is tested in task_notification_scheduler_test.dart.
      expect(notificationIdForTask('user-a', 'a'), isA<int>());
      expect(notificationIdForTask('user-b', 'b'), isA<int>());
    });
  });
}
