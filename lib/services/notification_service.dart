import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    
    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  Future<void> requestPermissions() async {
    await Permission.notification.request();
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  int _generateId(String name) {
    return name.hashCode;
  }

  Future<void> scheduleDueDateNotification(String username, DateTime dueDate) async {
    final id = _generateId(username);
    
    // Set for 9:00 AM on the due date
    var scheduledTime = DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0);
    
    if (scheduledTime.isBefore(DateTime.now())) {
      // If the time has already passed, don't schedule a past notification
      return; 
    }

    final tz.TZDateTime tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'pppoe_due_date_channel',
      'PPPoE Due Date Alerts',
      channelDescription: 'Notifications for PPPoE clients reaching their due date',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: 'Client Due Today: $username',
      body: 'PPPoE client $username has reached their billing due date.',
      scheduledDate: tzScheduledTime,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelNotification(String username) async {
    final id = _generateId(username);
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }
}
