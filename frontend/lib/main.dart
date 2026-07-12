import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:nutrifit/firebase_options.dart';
import 'package:nutrifit/logo_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  print("Background message: ${message.messageId}");
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tzdata.initializeTimeZones();

tz.setLocalLocation(tz.getLocation('Asia/Karachi'));

  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nutrifit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const LogoPage(),
    );
  }
}
