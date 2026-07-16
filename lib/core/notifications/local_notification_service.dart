import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  LocalNotificationService()
    : _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings: settings);
  }

  Future<void> scheduleTaskNotification(
    String id,
    String title,
    DateTime date,
  ) async {
    final tzDate = tz.TZDateTime.from(date, tz.local);
    await _plugin.zonedSchedule(
      id: id.hashCode,
      title: title,
      body: 'Tarefa vence hoje',
      scheduledDate: tzDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'tasks',
          'Tarefas',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id: id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
