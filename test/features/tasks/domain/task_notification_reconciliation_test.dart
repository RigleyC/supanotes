import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;

// Stub for the production TaskData model (defined in task_model.dart).
// Used here to characterize the reconcile API shape before implementation.
class _StubTaskData {
  final String id;
  _StubTaskData(this.id);
}

// Stub for the notification scheduler — reconcile(userId,tasks) will be
// the interface implemented in the consolidation plan (Task 7).
class _StubNotificationScheduler {
  Future<void> reconcile({
    required String userId,
    required List<_StubTaskData> tasks,
  }) async {
    // No-op — interface placeholder.
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

int notificationIdForTask(String taskId) => taskId.hashCode;

_StubTaskData task(String id) => _StubTaskData(id);

void main() {
  group('TaskNotificationScheduler - reconciliation', () {
    test(
        'switching user cancels the previous user schedule before scheduling the next',
        () async {
      final plugin = FakeNotificationPlugin();
      final scheduler = _StubNotificationScheduler();

      await scheduler.reconcile(userId: 'user-a', tasks: [task('a')]);
      await scheduler.reconcile(userId: 'user-b', tasks: [task('b')]);

      expect(plugin.cancelled, contains(notificationIdForTask('a')));
      expect(plugin.scheduledIds, contains(notificationIdForTask('b')));
    });
  });
}
