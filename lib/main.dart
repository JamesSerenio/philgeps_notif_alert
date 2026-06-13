import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'styles/app_styles.dart';
import 'utils/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.initialize();

  final token = await FirebaseMessaging.instance.getToken(
    vapidKey:
        'BKH3mkFzPUhN06q8LmpgXdsXwgfFY2coyzo1qBs2IH2qH_GdfP2VBLMgQRgpOLBtX2gkYp6OtP-qQbxjvTIRuJE',
  );

  debugPrint('FCM TOKEN: $token');

  runApp(const PhilgepsAlertApp());
}

class NotificationService {
  static Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await messaging.getToken(
      vapidKey:
          'BKH3mkFzPUhN06q8LmpgXdsXwgfFY2coyzo1qBs2IH2qH_GdfP2VBLMgQRgpOLBtX2gkYp6OtP-qQbxjvTIRuJE',
    );

    if (token != null) {
      try {
        await SupabaseConfig.client.from('device_tokens').upsert(
          {
            'token': token,
            'platform': 'web',
          },
          onConflict: 'token',
        );

        debugPrint('FCM token saved to Supabase.');
      } catch (e) {
        debugPrint('Token already saved or Supabase token save error: $e');
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground notification: ${message.notification?.title}');
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final url = message.data['url'];
      if (url != null) {
        openPhilgepsLink(url);
      }
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      final url = initialMessage.data['url'];
      if (url != null) {
        openPhilgepsLink(url);
      }
    }
  }
}

Future<void> openPhilgepsLink(String url) async {
  if (url.isEmpty) return;

  final uri = Uri.parse(url);

  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }
}

class PhilgepsAlertApp extends StatelessWidget {
  const PhilgepsAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhilGEPS Notif & Alert',
      debugShowCheckedModeBanner: false,
      theme: AppStyles.lightTheme,
      home: const HomePage(),
    );
  }
}

class ProjectPost {
  final String id;
  final String lgu;
  final String title;
  final String abc;
  final String closingDate;
  final String postingDate;
  final String url;

  ProjectPost({
    required this.id,
    required this.lgu,
    required this.title,
    required this.abc,
    required this.closingDate,
    required this.postingDate,
    required this.url,
  });

  factory ProjectPost.fromJson(Map<String, dynamic> json) {
    return ProjectPost(
      id: json['id']?.toString() ?? '',
      lgu: json['lgu']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      abc: json['abc']?.toString() ?? '',
      closingDate: json['closingDate']?.toString() ?? '',
      postingDate: json['postingDate']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }
}

enum DeadlineStatus { safe, near, urgent, closed, unknown }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController keywordController = TextEditingController();

  final List<String> lguList = [
    'alubijid',
    'lagonglong',
    'balingasag',
    'villanueva',
    'salay',
    'gitagum',
    'libertad',
    'initao',
    'naawan',
    'laguindingan',
    'talakag',
    'libona',
    'malitbog',
    'sumilao',
    'impasugong',
    'impasug-ong',
    'baungon',
  ];

  List<ProjectPost> posts = [];
  bool isLoading = false;
  String statusMessage = 'Monitoring PhilGEPS notifications...';

  final String apiUrl = 'YOUR_RAILWAY_BACKEND_URL/check';

  @override
  void initState() {
    super.initState();
    loadSavedData();
    loadPostsFromSupabase();
  }

  Future<void> loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      keywordController.text = prefs.getString('keywords') ?? '';
    });
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('keywords', keywordController.text);
  }

  Future<void> loadPostsFromSupabase() async {
    try {
      final response = await SupabaseConfig.client
          .from('philgeps_posts')
          .select()
          .order('closing_date', ascending: true);

      final items = response.map<ProjectPost>((item) {
        return ProjectPost(
          id: item['id']?.toString() ?? '',
          lgu: item['lgu']?.toString() ?? '',
          title: item['title']?.toString() ?? '',
          abc: item['abc']?.toString() ?? '',
          postingDate: item['posting_date']?.toString() ?? '',
          closingDate: item['closing_date']?.toString() ?? '',
          url: item['url']?.toString() ?? '',
        );
      }).toList();

      setState(() {
        posts = items;
        sortByDeadline();
        statusMessage = 'Loaded ${posts.length} post(s) from Supabase.';
      });
    } catch (e) {
      setState(() {
        statusMessage = 'Supabase connected, but no posts yet.';
      });
    }
  }

  Future<void> checkPhilgeps() async {
    if (apiUrl.contains('YOUR_RAILWAY_BACKEND_URL')) {
      await loadPostsFromSupabase();
      return;
    }

    setState(() {
      isLoading = true;
      statusMessage = 'Checking PhilGEPS through Railway...';
    });

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'lgus': lguList,
          'keywords': keywordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List items = data['items'] ?? [];

        setState(() {
          posts = items.map((e) => ProjectPost.fromJson(e)).toList();
          sortByDeadline();
          statusMessage = 'Found ${posts.length} matching post(s).';
        });
      } else {
        setState(() {
          statusMessage = 'Railway error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Cannot connect to Railway backend.';
      });
    }

    setState(() {
      isLoading = false;
    });
  }

  void sortByDeadline() {
    posts.sort((a, b) {
      final da = DateTime.tryParse(a.closingDate);
      final db = DateTime.tryParse(b.closingDate);

      if (da == null) return 1;
      if (db == null) return -1;

      return da.compareTo(db);
    });
  }

  bool isNewPost(ProjectPost post) {
    final posted = DateTime.tryParse(post.postingDate);
    if (posted == null) return false;
    return DateTime.now().difference(posted).inHours <= 24;
  }

  DeadlineStatus getDeadlineStatus(String dateText) {
    final date = DateTime.tryParse(dateText);

    if (date == null) return DeadlineStatus.unknown;

    final diff = date.difference(DateTime.now());

    if (diff.isNegative) return DeadlineStatus.closed;
    if (diff.inHours <= 24) return DeadlineStatus.urgent;
    if (diff.inHours <= 72) return DeadlineStatus.near;

    return DeadlineStatus.safe;
  }

  Color getStatusColor(DeadlineStatus status) {
    switch (status) {
      case DeadlineStatus.safe:
        return AppStyles.safe;
      case DeadlineStatus.near:
        return AppStyles.warning;
      case DeadlineStatus.urgent:
        return AppStyles.danger;
      case DeadlineStatus.closed:
        return AppStyles.old;
      case DeadlineStatus.unknown:
        return AppStyles.old;
    }
  }

  String getCountdown(String dateText) {
    final date = DateTime.tryParse(dateText);

    if (date == null) return 'No closing date found';

    final diff = date.difference(DateTime.now());

    if (diff.isNegative) return 'Closed';

    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;

    if (days > 0) return 'Closes in ${days}d ${hours}h';
    if (hours > 0) return 'Closes in ${hours}h ${minutes}m';

    return 'Closes in ${minutes}m';
  }

  String formatDate(String dateText) {
    final date = DateTime.tryParse(dateText);

    if (date == null) return dateText;

    return DateFormat('MMM dd, yyyy - hh:mm a').format(date);
  }

  int get urgentCount {
    return posts.where((post) {
      final s = getDeadlineStatus(post.closingDate);
      return s == DeadlineStatus.urgent || s == DeadlineStatus.near;
    }).length;
  }

  int get newCount {
    return posts.where(isNewPost).length;
  }

  double get maxWidth => 1180;

  Widget premiumCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppStyles.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE6E8DD)),
        boxShadow: [
          BoxShadow(
            color: AppStyles.deepGreen.withOpacity(0.06),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget badge({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withOpacity(0.13),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color.withOpacity(0.13),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHero(bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 34 : 24),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppStyles.deepGreen,
            AppStyles.primaryGreen,
            Color(0xFF1D6B43),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppStyles.deepGreen.withOpacity(0.22),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 20,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: isWide ? 620 : double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                badge(
                  text: 'LIVE PHILGEPS MONITOR',
                  color: AppStyles.gold,
                  icon: Icons.notifications_active,
                ),
                const SizedBox(height: 18),
                const Text(
                  'PhilGEPS Notif & Alert',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Automatic monitoring for selected LGUs with deadline alerts, new post tracking, and bid reminders.',
                  style: TextStyle(
                    color: Color(0xFFEAF6EF),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: isLoading ? null : checkPhilgeps,
            icon: isLoading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.search),
            label: Text(isLoading ? 'Checking...' : 'Check Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppStyles.gold,
              foregroundColor: AppStyles.deepGreen,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLguSection() {
    return premiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow(
            icon: Icons.location_city_rounded,
            title: 'Monitoring LGUs',
            subtitle: '${lguList.length} selected LGUs for notification alerts',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: lguList.map((lgu) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: AppStyles.softGreen,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppStyles.primaryGreen.withOpacity(0.16),
                  ),
                ),
                child: Text(
                  toTitleCase(lgu),
                  style: const TextStyle(
                    color: AppStyles.primaryGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget titleRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: AppStyles.softGold,
          child: Icon(icon, color: AppStyles.gold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101828),
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String toTitleCase(String value) {
    return value.split('-').map((part) {
      return part.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1);
      }).join(' ');
    }).join('-');
  }

  Widget buildFilterSection() {
    return premiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow(
            icon: Icons.tune_rounded,
            title: 'Keyword Filter',
            subtitle:
                'Optional filters for CCTV, LED Wall, Solar, Construction',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: keywordController,
            maxLines: 3,
            onChanged: (_) => saveData(),
            decoration: const InputDecoration(
              hintText: 'Example: CCTV, LED Wall, Solar',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildStats(bool isWide) {
    final cards = [
      statCard(
        label: 'Total Posts',
        value: posts.length.toString(),
        icon: Icons.article_rounded,
        color: AppStyles.primaryGreen,
      ),
      statCard(
        label: 'Near Deadline',
        value: urgentCount.toString(),
        icon: Icons.warning_amber_rounded,
        color: AppStyles.warning,
      ),
      statCard(
        label: 'New Posts',
        value: newCount.toString(),
        icon: Icons.fiber_new_rounded,
        color: AppStyles.gold,
      ),
    ];

    if (isWide) {
      return Row(
        children: cards
            .map(
              (card) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: card,
                ),
              ),
            )
            .toList(),
      );
    }

    return Column(
      children: cards
          .map(
            (card) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: card,
            ),
          )
          .toList(),
    );
  }

  Widget buildPostCard(ProjectPost post) {
    final deadlineStatus = getDeadlineStatus(post.closingDate);
    final statusColor = getStatusColor(deadlineStatus);
    final newPost = isNewPost(post);
    final closed = deadlineStatus == DeadlineStatus.closed;

    return InkWell(
      onTap: () => openPhilgepsLink(post.url),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: statusColor.withOpacity(0.28)),
          boxShadow: [
            BoxShadow(
              color: statusColor.withOpacity(0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                badge(
                  text: newPost ? 'NEW' : 'OLD',
                  color: newPost ? AppStyles.gold : AppStyles.old,
                  icon: newPost ? Icons.fiber_new_rounded : Icons.history,
                ),
                badge(
                  text: closed ? 'CLOSED' : getCountdown(post.closingDate),
                  color: statusColor,
                  icon: closed ? Icons.lock_clock : Icons.timer_rounded,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              post.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF101828),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            infoLine(Icons.location_city_rounded, toTitleCase(post.lgu)),
            infoLine(Icons.payments_rounded, 'ABC: ${post.abc}'),
            infoLine(
              Icons.calendar_month_rounded,
              'Posted: ${formatDate(post.postingDate)}',
            ),
            infoLine(
              Icons.event_available_rounded,
              'Closing: ${formatDate(post.closingDate)}',
              color: statusColor,
            ),
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.open_in_new, size: 17, color: AppStyles.gold),
                SizedBox(width: 6),
                Text(
                  'Tap to open PhilGEPS post',
                  style: TextStyle(
                    color: AppStyles.primaryGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget infoLine(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? AppStyles.primaryGreen),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? const Color(0xFF344054),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDashboard() {
    return premiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow(
            icon: Icons.dashboard_rounded,
            title: 'Bid Deadline Dashboard',
            subtitle: 'Nearest closing deadline appears first',
          ),
          const SizedBox(height: 18),
          if (posts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppStyles.softGreen,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 44,
                    color: AppStyles.primaryGreen,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'No posts yet',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Click Check Now to start monitoring.',
                    style: TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              ),
            )
          else
            ...posts.map(buildPostCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 850;

            return SingleChildScrollView(
              padding: EdgeInsets.all(isWide ? 26 : 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    children: [
                      buildHero(isWide),
                      buildStats(isWide),
                      const SizedBox(height: 18),
                      isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: buildLguSection()),
                                const SizedBox(width: 18),
                                Expanded(child: buildFilterSection()),
                              ],
                            )
                          : Column(
                              children: [
                                buildLguSection(),
                                buildFilterSection(),
                              ],
                            ),
                      premiumCard(
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: AppStyles.softGold,
                              child: Icon(
                                Icons.notifications_active_rounded,
                                color: AppStyles.gold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                statusMessage,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF344054),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      buildDashboard(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
