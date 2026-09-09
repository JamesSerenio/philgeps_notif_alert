part of '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  void _updateState(VoidCallback update) => setState(update);

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
    'manolo fortich',
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
        throw Exception('Failed to update bidding docs');
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
            deliveryPeriod: post.deliveryPeriod,
            classification: post.classification,
            abc: post.abc,
            budgetType: post.budgetType,
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

// await loadPostsFromSupabase();
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
    Future.microtask(() {
      loadSavedData();
      loadPostsFromSupabase();
    });
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

  Future<List<Map<String, dynamic>>> fetchAllPhilgepsPosts() async {
    const int pageSize = 1000;

    int from = 0;
    final List<Map<String, dynamic>> allRows = [];

    while (true) {
      final response = await SupabaseConfig.client
          .from('philgeps_posts')
          .select()
          .order('closing_date', ascending: true)
          .order('id', ascending: true)
          .range(from, from + pageSize - 1);

      final List<Map<String, dynamic>> currentPage =
          List<Map<String, dynamic>>.from(response);

      allRows.addAll(currentPage);

      // Kapag mas mababa na sa 1000 ang nakuha,
      // ibig sabihin nasa last page na.
      if (currentPage.length < pageSize) {
        break;
      }

      from += pageSize;
    }

    return allRows;
  }

  Future<void> loadPostsFromSupabase() async {
    try {
      final List<Map<String, dynamic>> response = await fetchAllPhilgepsPosts();

      final List<ProjectPost> items =
          response.map(ProjectPost.fromJson).toList();

      if (!mounted) return;

      setState(() {
        posts = items;
        sortByDeadline();

        statusMessage = 'Loaded all ${posts.length} post(s) from Supabase.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusMessage = 'Failed to load posts from Supabase: $e';
      });
    }
  }

  Future<void> checkPhilgeps() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      statusMessage = 'Checking PhilGEPS through Railway...';
    });

    try {
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'lgus': lguList,
              'keywords': keywordController.text.trim(),
            }),
          )
          .timeout(const Duration(minutes: 22));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;

        final bool busy = data['busy'] == true;
        final int checked = (data['checked'] as num?)?.toInt() ?? 0;
        final int totalStored = (data['totalStored'] as num?)?.toInt() ?? 0;

        final List<dynamic> items =
            data['items'] is List ? data['items'] as List<dynamic> : [];

        final loadedPosts = items
            .whereType<Map<String, dynamic>>()
            .map(ProjectPost.fromJson)
            .toList();

        setState(() {
          posts = loadedPosts;
          sortByDeadline();

          if (busy) {
            statusMessage =
                'Checker is still running. Showing $totalStored stored post(s).';
          } else if (checked > 0) {
            statusMessage = 'Check completed. $checked new post(s) processed. '
                '${posts.length} total active post(s).';
          } else {
            statusMessage = 'Check completed. No new post found. '
                '${posts.length} active post(s) stored.';
          }
        });
      } else {
        String errorMessage = 'Railway error: ${response.statusCode}';

        try {
          final data = jsonDecode(response.body);

          if (data is Map<String, dynamic> &&
              data['error']?.toString().isNotEmpty == true) {
            errorMessage = data['error'].toString();
          }
        } catch (_) {}

        setState(() {
          statusMessage = errorMessage;
        });
      }
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        statusMessage = 'The checker is taking longer than expected. '
            'It may still be running in Railway.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusMessage = 'Cannot connect to Railway backend: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void sortByDeadline() {
    posts.sort((a, b) {
      final aIsNew = a.status == 'new';
      final bIsNew = b.status == 'new';

      if (aIsNew && !bIsNew) return -1;
      if (!aIsNew && bIsNew) return 1;

      final aPosted = DateTime.tryParse(a.postingDate);
      final bPosted = DateTime.tryParse(b.postingDate);

      if (aPosted == null && bPosted == null) return 0;
      if (aPosted == null) return 1;
      if (bPosted == null) return -1;

      return bPosted.compareTo(aPosted);
    });
  }

  bool isNewPost(ProjectPost post) {
    final posted = DateTime.tryParse(post.postingDate);

    if (posted == null) return false;

    final postedPH = posted.toLocal();

    final ageHours = DateTime.now().difference(postedPH).inHours;

    return ageHours < 24;
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

    return DateFormat('MMM dd, yyyy - hh:mm a').format(
      date.toLocal(),
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
