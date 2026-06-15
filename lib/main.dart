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

  await NotificationService.initialize();

  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceKey = prefs.getString('device_key') ??
        '${DateTime.now().millisecondsSinceEpoch}-${defaultTargetPlatform.name}';

    await prefs.setString('device_key', deviceKey);

    await SupabaseConfig.client.from('device_tokens').upsert(
      {
        'token': token,
        'platform': 'web',
        'device_key': deviceKey,
      },
      onConflict: 'device_key',
    );
  });

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
        final prefs = await SharedPreferences.getInstance();
        final deviceKey = prefs.getString('device_key') ??
            '${DateTime.now().millisecondsSinceEpoch}-${defaultTargetPlatform.name}';

        await prefs.setString('device_key', deviceKey);

        await SupabaseConfig.client.from('device_tokens').upsert(
          {
            'token': token,
            'platform': 'web',
            'device_key': deviceKey,
          },
          onConflict: 'device_key',
        );
      } catch (e) {
        debugPrint('Supabase token save error: $e');
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? 'PhilGEPS Notif & Alert';
      final body = message.notification?.body ?? 'New PhilGEPS post detected.';
      final url = message.data['url'] ?? 'https://notices.philgeps.gov.ph/';

      showDialog(
        context: navigatorKey.currentContext!,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(navigatorKey.currentContext!),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(navigatorKey.currentContext!);
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

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final url = initialMessage.data['url'];
      if (url != null) openPhilgepsLink(url);
    }
  }
}

Future<void> openPhilgepsLink(String url) async {
  final refMatch = RegExp(r'refID=(\d+)', caseSensitive: false).firstMatch(url);

  if (refMatch == null) return;

  final finalUrl =
      'https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/SplashBidNoticeAbstractUI.aspx?menuIndex=3&refID=${refMatch.group(1)}&highlight=true';

  final uri = Uri.parse(finalUrl);

  await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

class ProjectPost {
  final String id;
  final String lgu;
  final String title;
  final String referenceNumber;
  final String procuringEntity;
  final String areaOfDelivery;
  final String classification;
  final double abc;
  final String closingDate;
  final String postingDate;
  final String url;
  final bool isBiddingDoc;
  final String status;

  ProjectPost({
    required this.id,
    required this.lgu,
    required this.title,
    required this.closingDate,
    required this.postingDate,
    required this.url,
    required this.referenceNumber,
    required this.procuringEntity,
    required this.areaOfDelivery,
    required this.classification,
    required this.abc,
    required this.isBiddingDoc,
    required this.status,
  });

  factory ProjectPost.fromJson(Map<String, dynamic> json) {
    return ProjectPost(
      id: json['id']?.toString() ?? '',
      lgu: json['lgu']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      referenceNumber: json['reference_number']?.toString() ??
          json['referenceNumber']?.toString() ??
          '',
      procuringEntity: json['procuring_entity']?.toString() ??
          json['procuringEntity']?.toString() ??
          '',
      areaOfDelivery: json['area_of_delivery']?.toString() ??
          json['areaOfDelivery']?.toString() ??
          '',
      classification: json['classification']?.toString() ?? '',
      abc: (json['abc'] ?? 0).toDouble(),
      isBiddingDoc: json['is_bidding_doc'] == true,
      status: json['status']?.toString() ?? 'old',
      closingDate: json['closingDate']?.toString() ??
          json['closing_date']?.toString() ??
          '',
      postingDate: json['postingDate']?.toString() ??
          json['posting_date']?.toString() ??
          '',
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
  String selectedStatFilter = 'all';
  Set<String> biddingDocsIds = {};

  Future<void> saveBiddingDocs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('bidding_docs_ids', biddingDocsIds.toList());
  }

  int get biddingDocsCount {
    return posts.where((post) => post.isBiddingDoc).length;
  }

  bool isInBiddingDocs(ProjectPost post) {
    return post.isBiddingDoc;
  }

  Future<void> toggleBiddingDocs(ProjectPost post) async {
    try {
      final newValue = !post.isBiddingDoc;

      final response = await http.post(
        Uri.parse(
          'https://philgepsnotifalert-production.up.railway.app/set-bidding-doc',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'postId': post.id,
          'isBiddingDoc': newValue,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed update');
      }

      setState(() {
        final index = posts.indexWhere((e) => e.id == post.id);

        if (index != -1) {
          posts[index] = ProjectPost(
            id: post.id,
            lgu: post.lgu,
            title: post.title,
            referenceNumber: post.referenceNumber,
            procuringEntity: post.procuringEntity,
            areaOfDelivery: post.areaOfDelivery,
            classification: post.classification,
            abc: post.abc,
            postingDate: post.postingDate,
            closingDate: post.closingDate,
            url: post.url,
            status: post.status,
            isBiddingDoc: newValue,
          );
        }

        statusMessage =
            newValue ? 'Added to Bidding Docs.' : 'Removed from Bidding Docs.';
      });

      await loadPostsFromSupabase();
    } catch (e) {
      setState(() {
        statusMessage = 'Failed to update Bidding Docs.';
      });
    }
  }

  final String apiUrl =
      'https://philgepsnotifalert-production.up.railway.app/check';

  double get maxWidth => 1180;

  int get urgentCount {
    return posts.where((post) {
      final s = getDeadlineStatus(post.closingDate);
      return s == DeadlineStatus.urgent || s == DeadlineStatus.near;
    }).length;
  }

  int get newCount {
    return posts.where((post) => post.status == 'new').length;
  }

  final NumberFormat abcFormatter = NumberFormat('#,##0.00', 'en_US');

  List<ProjectPost> get filteredPosts {
    final keyword = keywordController.text.toLowerCase().trim();

    List<ProjectPost> basePosts = posts;

    if (selectedStatFilter == 'near') {
      basePosts = posts.where((post) {
        final s = getDeadlineStatus(post.closingDate);
        return s == DeadlineStatus.urgent || s == DeadlineStatus.near;
      }).toList();
    }

    if (selectedStatFilter == 'new') {
      basePosts = posts.where((post) {
        return post.status == 'new';
      }).toList();
    }

    if (selectedStatFilter == 'bidding') {
      basePosts = posts.where((post) {
        return post.isBiddingDoc;
      }).toList();
    }

    if (keyword.isEmpty) return basePosts;

    return basePosts.where((post) {
      final searchableText = '''
${post.lgu}
${post.title}
${post.referenceNumber}
${post.procuringEntity}
${post.areaOfDelivery}
${post.classification}
${post.postingDate}
${post.closingDate}
${post.url}
${post.abc}
'''
          .toLowerCase();

      return searchableText.contains(keyword);
    }).toList();
  }

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
      biddingDocsIds = (prefs.getStringList('bidding_docs_ids') ?? []).toSet();
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
          referenceNumber: item['reference_number']?.toString() ?? '',
          procuringEntity: item['procuring_entity']?.toString() ?? '',
          areaOfDelivery: item['area_of_delivery']?.toString() ?? '',
          classification: item['classification']?.toString() ?? '',
          abc: (item['abc'] ?? 0).toDouble(),
          isBiddingDoc: item['is_bidding_doc'] == true,
          status: item['status']?.toString() ?? 'old',
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
      final aIsNew = a.status == 'new';
      final bIsNew = b.status == 'new';

      if (aIsNew && !bIsNew) return -1;
      if (!aIsNew && bIsNew) return 1;

      final da = DateTime.tryParse(a.closingDate);
      final db = DateTime.tryParse(b.closingDate);

      if (da == null) return 1;
      if (db == null) return -1;

      final aClosed = da.isBefore(DateTime.now());
      final bClosed = db.isBefore(DateTime.now());

      if (!aClosed && bClosed) return -1;
      if (aClosed && !bClosed) return 1;

      return da.compareTo(db);
    });
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
    if (date == null) return 'No closing date';

    final diff = date.difference(DateTime.now());

    if (diff.isNegative) return 'Closed';

    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;

    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';

    return '${minutes}m';
  }

  String formatDate(String dateText) {
    final date = DateTime.tryParse(dateText);
    if (date == null) return dateText;

    return DateFormat('MMM dd, yyyy - hh:mm a').format(date);
  }

  Widget premiumCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppStyles.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8DD)),
        boxShadow: [
          BoxShadow(
            color: AppStyles.deepGreen.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
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
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(isSelected ? 0.22 : 0.13),
              Colors.white,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.18),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildHero(bool isWide) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isWide ? 18 : 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isWide ? 24 : 20),
        gradient: const LinearGradient(
          colors: [
            AppStyles.deepGreen,
            AppStyles.primaryGreen,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                badge(
                  text: 'LIVE PHILGEPS MONITOR',
                  color: AppStyles.gold,
                  icon: Icons.notifications_active,
                ),
                const SizedBox(height: 8),
                Text(
                  'PhilGEPS Notif & Alert',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isWide ? 26 : 19,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Deadline alerts, new posts, and bid reminders.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFEAF6EF),
                    fontSize: isWide ? 13 : 10,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: isWide ? 40 : 34,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : checkPhilgeps,
              icon: isLoading
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search, size: 15),
              label: Text(isLoading ? '...' : 'Check'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyles.gold,
                foregroundColor: AppStyles.deepGreen,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
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
          radius: 18,
          backgroundColor: AppStyles.softGold,
          child: Icon(icon, color: AppStyles.gold, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101828),
                ),
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
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
            subtitle: 'Search by LGU, title, reference no., entity, or area',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: keywordController,
            maxLines: 1,
            onChanged: (_) {
              saveData();
              setState(() {});
            },
            decoration: const InputDecoration(
              hintText: 'Search CCTV, LED Wall, Solar, LGU...',
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
        label: 'Total',
        value: posts.length.toString(),
        icon: Icons.article_rounded,
        color: AppStyles.primaryGreen,
        isSelected: selectedStatFilter == 'all',
        onTap: () {
          setState(() {
            selectedStatFilter = 'all';
            statusMessage = 'Showing all PhilGEPS posts.';
          });
        },
      ),
      statCard(
        label: 'Deadline',
        value: urgentCount.toString(),
        icon: Icons.warning_amber_rounded,
        color: AppStyles.warning,
        isSelected: selectedStatFilter == 'near',
        onTap: () {
          setState(() {
            selectedStatFilter = 'near';
            statusMessage = 'Showing near deadline posts only.';
          });
        },
      ),
      statCard(
        label: 'New',
        value: newCount.toString(),
        icon: Icons.fiber_new_rounded,
        color: AppStyles.gold,
        isSelected: selectedStatFilter == 'new',
        onTap: () {
          setState(() {
            selectedStatFilter = 'new';
            statusMessage = 'Showing new PhilGEPS posts only.';
          });
        },
      ),
      statCard(
        label: 'Bidding Docs',
        value: biddingDocsCount.toString(),
        icon: Icons.thumb_up_alt_rounded,
        color: AppStyles.primaryGreen,
        isSelected: selectedStatFilter == 'bidding',
        onTap: () {
          setState(() {
            selectedStatFilter = 'bidding';
            statusMessage = 'Showing selected bidding documents.';
          });
        },
      ),
    ];

    return Row(
      children: List.generate(cards.length, (index) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == cards.length - 1 ? 0 : 6),
            child: SizedBox(
              height: isWide ? 76 : 62,
              child: cards[index],
            ),
          ),
        );
      }),
    );
  }

  Widget buildPostCard(ProjectPost post) {
    final deadlineStatus = getDeadlineStatus(post.closingDate);
    final statusColor = getStatusColor(deadlineStatus);
    final newPost = post.status == 'new';
    final closed = deadlineStatus == DeadlineStatus.closed;

    return InkWell(
      onTap: () => openPhilgepsLink(
        'https://notices.philgeps.gov.ph/GEPSNONPILOT/Tender/SplashBidNoticeAbstractUI.aspx?menuIndex=3&refID=${post.referenceNumber}&highlight=true',
      ),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: statusColor.withOpacity(0.28)),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
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
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 42),
                  child: Text(
                    post.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF101828),
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                infoLine(Icons.location_city_rounded, toTitleCase(post.lgu)),
                infoLine(
                  Icons.confirmation_number_rounded,
                  'Reference No.: ${post.referenceNumber}',
                ),
                infoLine(
                  Icons.business_rounded,
                  'Procuring Entity: ${post.procuringEntity}',
                ),
                infoLine(
                  Icons.place_rounded,
                  'Area of Delivery: ${post.areaOfDelivery}',
                ),
                infoLine(
                  Icons.category_rounded,
                  'Classification: ${post.classification}',
                ),
                infoLine(
                  Icons.payments_rounded,
                  'ABC: ${abcFormatter.format(post.abc)}',
                ),
                infoLine(
                  Icons.calendar_month_rounded,
                  'Posted: ${formatDate(post.postingDate)}',
                ),
                infoLine(
                  Icons.event_available_rounded,
                  'Closing: ${formatDate(post.closingDate)}',
                  color: statusColor,
                ),
                const SizedBox(height: 5),
                const Row(
                  children: [
                    Icon(Icons.open_in_new, size: 14, color: AppStyles.gold),
                    SizedBox(width: 5),
                    Text(
                      'Tap to open PhilGEPS post',
                      style: TextStyle(
                        color: AppStyles.primaryGreen,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: InkWell(
              onTap: () => toggleBiddingDocs(post),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isInBiddingDocs(post)
                      ? const Color(0xFFFFF1F1)
                      : AppStyles.softGreen,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isInBiddingDocs(post)
                        ? AppStyles.danger.withOpacity(0.4)
                        : AppStyles.primaryGreen,
                  ),
                ),
                child: Icon(
                  isInBiddingDocs(post)
                      ? Icons.thumb_down_alt_rounded
                      : Icons.thumb_up_alt_rounded,
                  size: 16,
                  color: isInBiddingDocs(post)
                      ? AppStyles.danger
                      : AppStyles.primaryGreen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget infoLine(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color ?? AppStyles.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? const Color(0xFF344054),
                fontWeight: FontWeight.w600,
                fontSize: 11,
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
          const SizedBox(height: 12),
          if (filteredPosts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppStyles.softGreen,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 38,
                    color: AppStyles.primaryGreen,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No posts yet',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Click Check to start monitoring.',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else
            ...filteredPosts.map(buildPostCard),
        ],
      ),
    );
  }

  Widget buildStatusMessage() {
    return premiumCard(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 17,
            backgroundColor: AppStyles.softGold,
            child: Icon(
              Icons.notifications_active_rounded,
              color: AppStyles.gold,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusMessage,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF344054),
                fontSize: 12,
              ),
            ),
          ),
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
              padding: EdgeInsets.all(isWide ? 22 : 10),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    children: [
                      buildHero(isWide),
                      buildStats(isWide),
                      const SizedBox(height: 8),
                      buildFilterSection(),
                      buildStatusMessage(),
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
