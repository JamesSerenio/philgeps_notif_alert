import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'styles/app_styles.dart';

void main() {
  runApp(const PhilgepsAlertApp());
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
      id: json['id'] ?? '',
      lgu: json['lgu'] ?? '',
      title: json['title'] ?? '',
      abc: json['abc'] ?? '',
      closingDate: json['closingDate'] ?? '',
      postingDate: json['postingDate'] ?? '',
      url: json['url'] ?? '',
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum DeadlineStatus { safe, near, urgent, closed, unknown }

class _HomePageState extends State<HomePage> {
  final TextEditingController keywordController = TextEditingController();

  List<String> lguList = [
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

  final String apiUrl = 'https://your-railway-backend.up.railway.app/check';

  @override
  void initState() {
    super.initState();
    loadSavedData();
  }

  Future<void> loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      keywordController.text = prefs.getString('keywords') ?? '';
    });
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'keywords',
      keywordController.text,
    );
  }

  Future<void> checkPhilgeps() async {
    setState(() {
      isLoading = true;
      statusMessage = 'Checking PhilGEPS...';
    });

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
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
        useDemoData();
      }
    } catch (e) {
      useDemoData();
    }

    setState(() {
      isLoading = false;
    });
  }

  void useDemoData() {
    final now = DateTime.now();

    setState(() {
      posts = [
        ProjectPost(
          id: 'demo1',
          lgu: 'Malitbog',
          title: 'Procurement of CCTV Surveillance System',
          abc: 'PHP 2,500,000.00',
          postingDate: now.subtract(const Duration(hours: 2)).toIso8601String(),
          closingDate: now.add(const Duration(days: 1)).toIso8601String(),
          url: 'https://notices.philgeps.gov.ph/',
        ),
        ProjectPost(
          id: 'demo2',
          lgu: 'Libona',
          title: 'Supply and Installation of LED Wall Display',
          abc: 'PHP 2,000,000.00',
          postingDate: now.subtract(const Duration(days: 1)).toIso8601String(),
          closingDate: now.add(const Duration(days: 4)).toIso8601String(),
          url: 'https://notices.philgeps.gov.ph/',
        ),
      ];

      sortByDeadline();

      statusMessage = 'Backend not connected yet. Showing demo data.';
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

  DeadlineStatus getDeadlineStatus(String dateText) {
    final date = DateTime.tryParse(dateText);

    if (date == null) {
      return DeadlineStatus.unknown;
    }

    final diff = date.difference(DateTime.now());

    if (diff.isNegative) {
      return DeadlineStatus.closed;
    }

    if (diff.inHours <= 24) {
      return DeadlineStatus.urgent;
    }

    if (diff.inHours <= 72) {
      return DeadlineStatus.near;
    }

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
        return Colors.grey;

      case DeadlineStatus.unknown:
        return Colors.black54;
    }
  }

  String getCountdown(String dateText) {
    final date = DateTime.tryParse(dateText);

    if (date == null) {
      return 'No closing date found';
    }

    final diff = date.difference(DateTime.now());

    if (diff.isNegative) {
      return 'Closed';
    }

    final days = diff.inDays;
    final hours = diff.inHours % 24;

    return 'Closes in ${days}d ${hours}h';
  }

  String formatDate(String dateText) {
    final date = DateTime.tryParse(dateText);

    if (date == null) return dateText;

    return DateFormat(
      'MMM dd, yyyy - hh:mm a',
    ).format(date);
  }

  Widget sectionCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppStyles.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget buildPostCard(ProjectPost post) {
    final deadlineStatus = getDeadlineStatus(post.closingDate);

    final statusColor = getStatusColor(deadlineStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: statusColor.withOpacity(0.35),
        ),
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            post.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            post.lgu,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text('ABC: ${post.abc}'),
          const SizedBox(height: 8),
          Text(
            'Posted: ${formatDate(post.postingDate)}',
          ),
          const SizedBox(height: 8),
          Text(
            '${getCountdown(post.closingDate)} • ${formatDate(post.closingDate)}',
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urgentCount = posts.where((post) {
      final s = getDeadlineStatus(post.closingDate);

      return s == DeadlineStatus.urgent || s == DeadlineStatus.near;
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PhilGEPS Notif & Alert'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monitoring LGUs',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: lguList.map((lgu) {
                        return Chip(
                          label: Text(lgu),
                          backgroundColor: const Color(
                            0xFFE8F0FF,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Keyword Filter',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keywordController,
                      maxLines: 3,
                      onChanged: (_) {
                        saveData();
                      },
                      decoration: const InputDecoration(
                        hintText: 'Example: CCTV, LED Wall, Solar',
                      ),
                    ),
                  ],
                ),
              ),
              sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alert Controls',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: isLoading ? null : checkPhilgeps,
                      icon: isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.search,
                            ),
                      label: Text(
                        isLoading ? 'Checking...' : 'Check Now',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      statusMessage,
                      style: const TextStyle(
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              sectionCard(
                child: Row(
                  children: [
                    Expanded(
                      child: dashboardItem(
                        title: 'Total Posts',
                        value: posts.length.toString(),
                        icon: Icons.article,
                        color: AppStyles.primary,
                      ),
                    ),
                    Expanded(
                      child: dashboardItem(
                        title: 'Near Deadline',
                        value: urgentCount.toString(),
                        icon: Icons.warning,
                        color: AppStyles.warning,
                      ),
                    ),
                  ],
                ),
              ),
              sectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bid Deadline Dashboard',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (posts.isEmpty)
                      const Text(
                        'No posts yet.',
                        style: TextStyle(
                          color: Colors.black54,
                        ),
                      )
                    else
                      ...posts.map(
                        buildPostCard,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget dashboardItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
