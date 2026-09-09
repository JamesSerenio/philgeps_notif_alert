part of '../main.dart';

class NotificationService {
  static Future<void> saveDeviceToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = prefs.getString('device_key') ??
        '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch}-${defaultTargetPlatform.name}';
    await prefs.setString('device_key', deviceKey);

    await SupabaseConfig.client.rpc(
      'register_device_token',
      params: {
        'p_token': token,
        'p_platform': defaultTargetPlatform.name,
        'p_device_key': deviceKey,
      },
    );
  }

  static Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('Notification permission: ${settings.authorizationStatus}');

    final token = await messaging.getToken(
      vapidKey:
          'BKH3mkFzPUhN06q8LmpgXdsXwgfFY2coyzo1qBs2IH2qH_GdfP2VBLMgQRgpOLBtX2gkYp6OtP-qQbxjvTIRuJE',
    );

    if (token != null) {
      try {
        await saveDeviceToken(token);

        debugPrint('FCM token registered successfully.');
      } catch (e) {
        debugPrint('Supabase token save error: $e');
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ??
          message.data['title'] ??
          'PhilGEPS Notif & Alert';

      final body = message.notification?.body ??
          message.data['body'] ??
          'New PhilGEPS post detected.';
      final url = message.data['url'] ?? 'https://notices.philgeps.gov.ph/';

      final context = navigatorKey.currentContext;
      if (context == null) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openPhilgepsLink(url);
              },
              child: const Text('Open'),
            ),
          ],
        ),
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final url = message.data['url'];
      if (url != null) openPhilgepsLink(url);
    });

    // getInitialMessage is intended for app launches from a terminated state.
    // On Web, the Firebase JS bridge can try to clean up an iframe that is no
    // longer attached during hot reload and throw removeChild(null).
    if (!kIsWeb) {
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        final url = initialMessage.data['url'];
        if (url != null) openPhilgepsLink(url);
      }
    }
  }
}

Future<void> openPhilgepsLink(String url) async {
  if (url.isEmpty) return;

  final uri = Uri.parse(url);

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
