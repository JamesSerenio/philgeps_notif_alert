part of '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _refreshTimer;
  RealtimeChannel? _postsChannel;
  Future<void>? _postsLoad;
  bool _lastPostsLoadSucceeded = false;
  int _decisionVersion = 0;

  void _refreshPosts() {
    if (mounted &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
      unawaited(loadPostsFromSupabase());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPosts();
  }

  void _updateState(VoidCallback update) => setState(update);

  final _filterChanges = ValueNotifier<int>(0);

  final _parsedDates = <String, DateTime?>{};

  final _formattedDates = <String, String>{};

  final _dateFormat = DateFormat(
    'MMM dd, yyyy - hh:mm a',
  );

  DateTime? _parseDate(String value) {
    return _parsedDates.putIfAbsent(
      value,
      () => parsePhilgepsDate(value),
    );
  }

  void _selectFilter(
    String filter,
    String message,
  ) {
    if (selectedStatFilter == filter) {
      return;
    }

    selectedStatFilter = filter;
    statusMessage = message;

    _filterChanges.value++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    final channel = _postsChannel;
    if (channel != null)
      unawaited(SupabaseConfig.client.removeChannel(channel));
    _filterChanges.dispose();
    keywordController.dispose();

    super.dispose();
  }

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
  String checkButtonLabel = 'Check Updates';
  DateTime? lastSuccessfulScrape;

  String get lastScrapeLabel => lastSuccessfulScrape == null
      ? 'Last successful check: unavailable'
      : 'Last successful check: ${DateFormat('MMM dd, yyyy - hh:mm a').format(lastSuccessfulScrape!.toUtc().add(const Duration(hours: 8)))} PHT';

  Future<void> loadLastSuccessfulScrape() async {
    try {
      final response = await http
          .get(Uri.parse('$backendUrl/check/last-success'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final time = DateTime.tryParse(data['lastSuccessAt']?.toString() ?? '');
      if (mounted)
        setState(() {
          lastSuccessfulScrape = time;
          sourceRefresh = (data['sources'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
    } catch (_) {/* A metadata failure must not interrupt the dashboard. */}
  }

  String statusMessage = 'Monitoring PhilGEPS notifications...';

  String selectedStatFilter = 'all';
  String selectedSource = 'all';
  DateTime? publicationFrom, publicationTo, closingFrom, closingTo;
  List<Map<String, dynamic>> sourceRefresh = [];

  Set<String> biddingDocsIds = {};

  // Used so buttons cannot be clicked repeatedly
  // while one project is being updated.
  String? _processingPostId;

  bool isProcessingPost(
    ProjectPost post,
  ) {
    return _processingPostId == post.id;
  }

  Future<void> saveBiddingDocs() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      'bidding_docs_ids',
      biddingDocsIds.toList(),
    );
  }

  // ---------------------------------------------------------
  // BIDDING DOCUMENT / DONE COUNTS
  // ---------------------------------------------------------

  int get biddingDocsCount {
    return posts
        .where(
          (post) => post.isBiddingDoc && !post.isDone,
        )
        .length;
  }

  int get doneCount {
    return posts
        .where(
          (post) => post.isDone,
        )
        .length;
  }

  bool isInBiddingDocs(
    ProjectPost post,
  ) {
    return post.isBiddingDoc && !post.isDone;
  }

  // ---------------------------------------------------------
  // THUMBS-UP / BIDDING DOCUMENT
  // ---------------------------------------------------------

  Future<void> toggleBiddingDocs(
    ProjectPost post,
  ) async {
    if (_processingPostId != null) {
      return;
    }

    final newValue = !post.isBiddingDoc;

    setState(() {
      _processingPostId = post.id;
    });

    _decisionVersion++;
    try {
      await SupabaseConfig.client.rpc(
        'set_bid_doc_state',
        params: {
          'p_post_id': post.id,
          'p_value': newValue,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final index = posts.indexWhere(
          (item) => item.id == post.id,
        );

        if (index != -1) {
          _decisionVersion++;
          posts[index] = posts[index].copyWith(
            isBiddingDoc: newValue,

            // If it is thumbed-up again,
            // remove it from Done.
            isDone: newValue ? false : posts[index].isDone,

            clearDoneAt: newValue,
          );
        }

        _processingPostId = null;

        statusMessage = newValue
            ? 'Added to Bidding Documents.'
            : 'Removed from Bidding Documents.';
      });

      _filterChanges.value++;
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processingPostId = null;

        statusMessage = 'Failed to update Bidding Documents: $e';
      });
    }
  }

  // ---------------------------------------------------------
  // DONE WORKFLOW
  // ---------------------------------------------------------

  Future<bool> _confirmMarkDone(
    ProjectPost post,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              16,
            ),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: Color(
                  0xFF087A55,
                ),
              ),
              SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  'Mark as Done?',
                ),
              ),
            ],
          ),
          content: Text(
            'The bid documents for:\n\n'
            '${post.title}\n\n'
            'will be marked as completed.\n\n'
            'The thumbs-up will automatically be removed '
            'and this project will move to Done.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'CANCEL',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(
                  0xFF087A55,
                ),
              ),
              icon: const Icon(
                Icons.check_rounded,
              ),
              label: const Text(
                'MARK AS DONE',
              ),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> markBiddingDocsDone(
    ProjectPost post,
  ) async {
    if (_processingPostId != null) {
      return;
    }

    if (!post.isBiddingDoc) {
      return;
    }

    final confirmed = await _confirmMarkDone(
      post,
    );

    if (!confirmed) {
      return;
    }

    setState(() {
      _processingPostId = post.id;
    });

    _decisionVersion++;
    try {
      await SupabaseConfig.client.rpc(
        'mark_bid_docs_done',
        params: {
          'p_post_id': post.id,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final index = posts.indexWhere(
          (item) => item.id == post.id,
        );

        if (index != -1) {
          _decisionVersion++;
          posts[index] = posts[index].copyWith(
            isBiddingDoc: false,
            isDone: true,
            doneAt: DateTime.now(),
          );
        }

        _processingPostId = null;

        statusMessage = 'Bid documents marked as Done.';
      });

      _filterChanges.value++;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bid documents completed. Project moved to Done.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processingPostId = null;

        statusMessage = 'Failed to mark bidding documents as Done: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to mark as Done: $e',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> undoBiddingDocsDone(
    ProjectPost post,
  ) async {
    if (_processingPostId != null) {
      return;
    }

    setState(() {
      _processingPostId = post.id;
    });

    _decisionVersion++;
    try {
      await SupabaseConfig.client.rpc(
        'undo_bid_docs_done',
        params: {
          'p_post_id': post.id,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final index = posts.indexWhere(
          (item) => item.id == post.id,
        );

        if (index != -1) {
          _decisionVersion++;
          posts[index] = posts[index].copyWith(
            isDone: false,
            clearDoneAt: true,
          );
        }

        _processingPostId = null;

        statusMessage = 'Done status removed.';
      });

      _filterChanges.value++;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Done status removed.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processingPostId = null;

        statusMessage = 'Failed to undo Done status: $e';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to undo Done: $e',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // API
  // ---------------------------------------------------------

  static const backendUrl = String.fromEnvironment('SCRAPER_BACKEND_URL',
      defaultValue: 'https://philgepsnotifalert-production.up.railway.app');

  double get maxWidth => 1240;

  int get urgentCount {
    return posts.where(
      (post) {
        final s = getDeadlineStatus(
          post.closingDate,
        );

        return s == DeadlineStatus.urgent || s == DeadlineStatus.near;
      },
    ).length;
  }

  int get newCount {
    return posts
        .where(
          (post) => isNewPost(post),
        )
        .length;
  }

  final NumberFormat abcFormatter = NumberFormat(
    '#,##0.00',
    'en_US',
  );

  // ---------------------------------------------------------
  // FILTERING
  // ---------------------------------------------------------

  List<ProjectPost> get filteredPosts {
    final keyword = keywordController.text.toLowerCase().trim();

    List<ProjectPost> basePosts = posts;

    if (selectedStatFilter == 'near') {
      basePosts = posts.where(
        (post) {
          final s = getDeadlineStatus(
            post.closingDate,
          );

          return s == DeadlineStatus.urgent || s == DeadlineStatus.near;
        },
      ).toList();
    }

    if (selectedStatFilter == 'new') {
      basePosts = posts.where(
        (post) {
          return isNewPost(post);
        },
      ).toList();
    }

    if (selectedStatFilter == 'bidding') {
      basePosts = posts.where(
        (post) {
          return post.isBiddingDoc && !post.isDone;
        },
      ).toList();
    }

    if (selectedStatFilter == 'done') {
      basePosts = posts.where(
        (post) {
          return post.isDone;
        },
      ).toList();
    }

    bool inRange(String value, DateTime? from, DateTime? to) {
      if (from == null && to == null) return true;
      final instant = _parseDate(value);
      if (instant == null) return false;
      final local = philippineTime(instant);
      final day = DateTime(local.year, local.month, local.day);
      return (from == null || !day.isBefore(from)) &&
          (to == null || !day.isAfter(to));
    }

    basePosts = basePosts
        .where((post) =>
            (selectedSource == 'all' || post.source == selectedSource) &&
            inRange(post.postingDate, publicationFrom, publicationTo) &&
            inRange(post.closingDate, closingFrom, closingTo))
        .toList();
    if (keyword.isEmpty) {
      return basePosts;
    }

    return basePosts.where(
      (post) {
        final searchableText = '''
${post.lgu}
${post.title}
${post.referenceNumber}
${post.procuringEntity}
${post.areaOfDelivery}
${post.deliveryPeriod}
${post.classification}
${post.procurementMode}
${post.sourceLabel}
${post.postingDate}
${post.closingDate}
${post.url}
${post.abc}
'''
            .toLowerCase();

        return searchableText.contains(
          keyword,
        );
      },
    ).toList();
  }

  // ---------------------------------------------------------
  // INITIAL LOAD
  // ---------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() {});
        _filterChanges.value++;
      }
      _refreshPosts();
      unawaited(loadLastSuccessfulScrape());
    });
    _postsChannel = SupabaseConfig.client
        .channel('dashboard-posts')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'philgeps_posts',
            callback: (_) => _refreshPosts())
        .subscribe();

    Future.microtask(
      () {
        loadSavedData();
        loadPostsFromSupabase();
        loadLastSuccessfulScrape();
      },
    );
  }

  Future<void> loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) {
      return;
    }

    setState(() {
      final savedSource = prefs.getString('opportunity_source') ?? 'all';
      selectedSource = const ['all', 'existing', 'modern'].contains(savedSource)
          ? savedSource
          : 'all';
      keywordController.text = prefs.getString(
            'keywords',
          ) ??
          '';

      biddingDocsIds = (prefs.getStringList(
                'bidding_docs_ids',
              ) ??
              [])
          .toSet();
    });
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('opportunity_source', selectedSource);

    await prefs.setString(
      'keywords',
      keywordController.text,
    );
  }

  // ---------------------------------------------------------
  // LOAD ALL SUPABASE POSTS
  // ---------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchAllPhilgepsPosts() async {
    const int pageSize = 1000;

    int from = 0;

    final List<Map<String, dynamic>> allRows = [];

    while (true) {
      final response = await SupabaseConfig.client
          .from(
            'philgeps_posts',
          )
          .select()
          .order(
            'created_at',
            ascending: false,
          )
          .order(
            'id',
            ascending: false,
          )
          .range(
            from,
            from + pageSize - 1,
          );

      final List<Map<String, dynamic>> currentPage =
          List<Map<String, dynamic>>.from(
        response,
      );

      allRows.addAll(
        currentPage,
      );

      // If fewer than 1000 records were returned,
      // this is the final page.
      if (currentPage.length < pageSize) {
        break;
      }

      from += pageSize;
    }

    return allRows;
  }

  Future<void> loadPostsFromSupabase() {
    final active = _postsLoad;
    if (active != null) return active;
    final request = _loadPostsFromSupabase();
    _postsLoad = request;
    return request.whenComplete(() {
      _postsLoad = null;
    });
  }

  Future<void> _loadPostsFromSupabase() async {
    final decisionVersion = _decisionVersion;
    try {
      final List<Map<String, dynamic>> response = await fetchAllPhilgepsPosts();

      // ProjectPost.fromJson now also reads:
      // is_bidding_doc
      // is_done
      // done_at
      final List<ProjectPost> items = response
          .map(
            ProjectPost.fromJson,
          )
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        // Keep decisions changed locally while this request was in flight.
        posts = decisionVersion == _decisionVersion
            ? items
            : items.map((item) {
                final matches = posts.where((p) => p.id == item.id);
                final previous = matches.isEmpty ? null : matches.first;
                return previous == null
                    ? item
                    : item.copyWith(
                        isBiddingDoc: previous.isBiddingDoc,
                        isDone: previous.isDone,
                        doneAt: previous.doneAt,
                        clearDoneAt: previous.doneAt == null);
              }).toList();

        sortByDeadline();

        statusMessage = 'Loaded all ${posts.length} post(s) from Supabase.';
        _lastPostsLoadSucceeded = true;
      });

      _filterChanges.value++;
    } catch (e) {
      _lastPostsLoadSucceeded = false;
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage = 'Failed to load posts from Supabase: $e';
      });
    }
  }

  // ---------------------------------------------------------
  // CHECK PHILGEPS
  // ---------------------------------------------------------

  Future<void> checkPhilgeps() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
      checkButtonLabel = 'Checking PhilGEPS...';
    });
    ScrapeApi? api;
    try {
      if (SupabaseConfig.client.auth.currentSession == null) {
        final signedIn = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _ScraperSignIn());
        if (!mounted) return;
        if (signedIn != true) {
          setState(() => checkButtonLabel = 'Check Updates');
          return;
        }
      }
      if (!mounted) return;
      setState(() =>
          statusMessage = 'Checking all monitored LGUs through Railway...');
      api = ScrapeApi(
          baseUrl: backendUrl,
          accessToken: () async {
            var session = SupabaseConfig.client.auth.currentSession;
            if (session != null && session.isExpired) {
              session =
                  (await SupabaseConfig.client.auth.refreshSession()).session;
            }
            if (session == null)
              throw Exception('Sign in again to check updates.');
            return session.accessToken;
          });
      final result = await api.check();
      if (!mounted) return;
      // Fetch a fresh complete dataset only after confirmed backend completion.
      // Wait for any older in-flight request before issuing this final refresh.
      final pending = _postsLoad;
      if (pending != null) await pending;
      await loadPostsFromSupabase();
      if (!mounted) return;
      if (!_lastPostsLoadSucceeded) {
        throw Exception(
            'Scrape completed, but the dashboard could not refresh: $statusMessage');
      }
      final run = result['run'] as Map<String, dynamic>;
      final newCount = (run['newCount'] as num?)?.toInt() ?? 0;
      setState(() {
        checkButtonLabel = newCount == 0
            ? 'No new opportunities found'
            : 'Updated successfully';
        lastSuccessfulScrape =
            DateTime.tryParse(result['lastSuccessAt']?.toString() ?? '');
        statusMessage = newCount == 0
            ? 'Check completed. No new opportunities found.'
            : 'Check completed. $newCount new opportunities found.';
      });
      _filterChanges.value++;
    } catch (error) {
      if (mounted) {
        setState(() {
          checkButtonLabel = 'Update failed \u2014 Retry';
          statusMessage = 'Update failed: $error';
        });
        _filterChanges.value++;
      }
    } finally {
      api?.close();
      await loadLastSuccessfulScrape();
      // A partial source failure may still have saved opportunities from the other portal.
      if (mounted) await loadPostsFromSupabase();
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ---------------------------------------------------------
  // SORTING
  // ---------------------------------------------------------

  void sortByDeadline() {
    posts.sort((a, b) {
      final aDate = a.discoveredAt;
      final bDate = b.discoveredAt;
      if (aDate == null && bDate == null) return b.id.compareTo(a.id);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final order = bDate.compareTo(aDate);
      return order == 0 ? b.id.compareTo(a.id) : order;
    });
  }

  bool isNewPost(ProjectPost post) =>
      discoveredWithin24Hours(post.discoveredAt);

  // ---------------------------------------------------------
  // DEADLINE HELPERS
  // ---------------------------------------------------------

  DeadlineStatus getDeadlineStatus(
    String dateText,
  ) {
    final date = _parseDate(
      dateText,
    );

    if (date == null) {
      return DeadlineStatus.unknown;
    }

    final diff = date.difference(
      DateTime.now(),
    );

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

  Color getStatusColor(
    DeadlineStatus status,
  ) {
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

  String getCountdown(
    String dateText,
  ) {
    final date = _parseDate(
      dateText,
    );

    if (date == null) {
      return 'No closing date';
    }

    final diff = date.difference(
      DateTime.now(),
    );

    if (diff.isNegative) {
      return 'Closed';
    }

    final days = diff.inDays;

    final hours = diff.inHours % 24;

    final minutes = diff.inMinutes % 60;

    if (days > 0) {
      return '${days}d ${hours}h';
    }

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    return '${minutes}m';
  }

  String formatDate(
    String dateText,
  ) {
    return _formattedDates.putIfAbsent(
      dateText,
      () {
        final date = _parseDate(
          dateText,
        );

        return date == null
            ? dateText
            : _dateFormat.format(
                date.toLocal(),
              );
      },
    );
  }

  String formatDoneDate(
    DateTime? date,
  ) {
    if (date == null) {
      return '';
    }

    return _dateFormat.format(
      date.toLocal(),
    );
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: _DashboardColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final isWide = constraints.maxWidth >= 850;

            final pagePadding = isWide ? 24.0 : 16.0;

            final horizontal = constraints.maxWidth > maxWidth + pagePadding * 2
                ? (constraints.maxWidth - maxWidth) / 2
                : pagePadding;

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    pagePadding,
                    horizontal,
                    20,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: buildHero(
                      isWide,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    0,
                    horizontal,
                    pagePadding,
                  ),
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFFCFDFC,
                      ),
                      border: Border.all(
                        color: const Color(
                          0xFFE5E7EB,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(
                        18,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.025,
                          ),
                          blurRadius: 16,
                          offset: const Offset(
                            0,
                            4,
                          ),
                        ),
                      ],
                    ),
                    sliver: SliverPadding(
                      padding: EdgeInsets.all(
                        isWide ? 24 : 20,
                      ),
                      sliver: ValueListenableBuilder<int>(
                        valueListenable: _filterChanges,

                        // Filter changes reuse the search subtree
                        // and leave the header alone.
                        child: buildFilterSection(),

                        builder: (
                          context,
                          _,
                          search,
                        ) {
                          final visiblePosts = filteredPosts;

                          return SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    buildStats(
                                      isWide,
                                    ),
                                    const SizedBox(
                                      height: 20,
                                    ),
                                    search!,
                                    buildStatusMessage(
                                      visiblePosts.length,
                                    ),
                                  ],
                                ),
                              ),
                              buildDashboard(
                                visiblePosts,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
