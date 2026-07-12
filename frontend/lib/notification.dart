import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {

    await _messaging.requestPermission();

    // Android initialization
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    // ✅ FIX: correct initialize (NO named parameter)
    await _localNotifications.initialize(settings: initSettings);

    String? token = await _messaging.getToken();
    print("FCM TOKEN: $token");

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showNotification(
          message.notification!.title ?? "Nutrifit",
          message.notification!.body ?? "",
          Duration()
        );
      }
    });
  }

  Future<void> showNotification(String title, String body, Duration duration) async {
final int id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'nutrifit_channel',
    'Nutrifit Notifications',
    importance: Importance.max,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(
      '',
    ),
  );

  const NotificationDetails details =
      NotificationDetails(android: androidDetails);

  // ✅ Show immediately
  await _localNotifications.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: details,
  );

 await _localNotifications.zonedSchedule(
  id: id + 1,
 matchDateTimeComponents: DateTimeComponents.time,
  title: title,
  body: body,
  scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(hours: 12)),
  notificationDetails: details,
  androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
);}}