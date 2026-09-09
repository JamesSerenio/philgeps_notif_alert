import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'styles/app_styles.dart';
import 'utils/supabase_client.dart';
import 'pdf_editor/screens/pdf_editor_screen.dart';

part 'services/notification_service.dart';
part 'models/project_post.dart';
part 'screens/home_page.dart';
part 'widgets/home/dashboard_sections.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  debugPrint('Background notification: ${message.notification?.title}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      NotificationService.initialize().catchError(
        (Object error, StackTrace stackTrace) {
          debugPrint('Notification initialization skipped: $error');
        },
      ),
    );
  });

  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    try {
      await NotificationService.saveDeviceToken(token);
    } catch (error) {
      debugPrint('Notification token refresh save skipped: $error');
    }
  });

// Removed from startup para mas paspas mo-open ang app.

  runApp(const PhilgepsAlertApp());
}

class PhilgepsAlertApp extends StatelessWidget {
  const PhilgepsAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'PhilGEPS Notif & Alert',
      debugShowCheckedModeBanner: false,
      theme: AppStyles.lightTheme,
      home: const HomePage(),
    );
  }
}
