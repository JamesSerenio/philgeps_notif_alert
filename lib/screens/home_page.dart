part of '../main.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
      () => DateTime.tryParse(value),
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
    _filterChanges.dispose();
    keywordController.dispose();

    super.dispose();
  }

  final TextEditingController keywordController =
      TextEditingController();

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

  String statusMessage =
      'Monitoring PhilGEPS notifications...';

  String selectedStatFilter = 'all';

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
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setStringList(
      'bidding_docs_ids',
      biddingDocsIds.toList(),
    );
  }

  // ---------------------------------------------------------
  // BIDDING DOCUMENT / DONE COUNTS
  // ---------------------------------------------------------

  int get biddingDocsCount {
    return posts.where(
      (post) =>
          post.isBiddingDoc &&
          !post.isDone,
    ).length;
  }

  int get doneCount {
    return posts.where(
      (post) => post.isDone,
    ).length;
  }

  bool isInBiddingDocs(
    ProjectPost post,
  ) {
    return post.isBiddingDoc &&
        !post.isDone;
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

    final newValue =
        !post.isBiddingDoc;

    setState(() {
      _processingPostId =
          post.id;
    });

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
          (item) =>
              item.id == post.id,
        );

        if (index != -1) {
          posts[index] =
              posts[index].copyWith(
            isBiddingDoc:
                newValue,

            // If it is thumbed-up again,
            // remove it from Done.
            isDone:
                newValue
                    ? false
                    : posts[index].isDone,

            clearDoneAt:
                newValue,
          );
        }

        _processingPostId = null;

        statusMessage =
            newValue
                ? 'Added to Bidding Documents.'
                : 'Removed from Bidding Documents.';
      });

      _filterChanges.value++;
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processingPostId =
            null;

        statusMessage =
            'Failed to update Bidding Documents: $e';
      });
    }
  }

  // ---------------------------------------------------------
  // DONE WORKFLOW
  // ---------------------------------------------------------

  Future<bool> _confirmMarkDone(
    ProjectPost post,
  ) async {
    final result =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              16,
            ),
          ),
          title: const Row(
            children: [
              Icon(
                Icons
                    .check_circle_outline_rounded,
                color:
                    Color(
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
              child:
                  const Text(
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
              style:
                  FilledButton
                      .styleFrom(
                backgroundColor:
                    const Color(
                  0xFF087A55,
                ),
              ),
              icon:
                  const Icon(
                Icons
                    .check_rounded,
              ),
              label:
                  const Text(
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

    final confirmed =
        await _confirmMarkDone(
      post,
    );

    if (!confirmed) {
      return;
    }

    setState(() {
      _processingPostId =
          post.id;
    });

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
          (item) =>
              item.id == post.id,
        );

        if (index != -1) {
          posts[index] =
              posts[index].copyWith(
            isBiddingDoc:
                false,
            isDone:
                true,
            doneAt:
                DateTime.now(),
          );
        }

        _processingPostId =
            null;

        statusMessage =
            'Bid documents marked as Done.';
      });

      _filterChanges.value++;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Bid documents completed. Project moved to Done.',
          ),
          behavior:
              SnackBarBehavior
                  .floating,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processingPostId =
            null;

        statusMessage =
            'Failed to mark bidding documents as Done: $e';
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to mark as Done: $e',
          ),
          behavior:
              SnackBarBehavior
                  .floating,
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
      _processingPostId =
          post.id;
    });

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
          (item) =>
              item.id == post.id,
        );

        if (index != -1) {
          posts[index] =
              posts[index].copyWith(
            isDone:
                false,
            clearDoneAt:
                true,
          );
        }

        _processingPostId =
            null;

        statusMessage =
            'Done status removed.';
      });

      _filterChanges.value++;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Done status removed.',
          ),
          behavior:
              SnackBarBehavior
                  .floating,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _processingPostId =
            null;

        statusMessage =
            'Failed to undo Done status: $e';
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to undo Done: $e',
          ),
          behavior:
              SnackBarBehavior
                  .floating,
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // API
  // ---------------------------------------------------------

  final String apiUrl =
      'https://philgepsnotifalert-production.up.railway.app/check';

  double get maxWidth =>
      1240;

  int get urgentCount {
    return posts.where(
      (post) {
        final s =
            getDeadlineStatus(
          post.closingDate,
        );

        return s ==
                DeadlineStatus
                    .urgent ||
            s ==
                DeadlineStatus
                    .near;
      },
    ).length;
  }

  int get newCount {
    return posts.where(
      (post) =>
          post.status ==
          'new',
    ).length;
  }

  final NumberFormat abcFormatter =
      NumberFormat(
    '#,##0.00',
    'en_US',
  );

  // ---------------------------------------------------------
  // FILTERING
  // ---------------------------------------------------------

  List<ProjectPost> get filteredPosts {
    final keyword =
        keywordController.text
            .toLowerCase()
            .trim();

    List<ProjectPost> basePosts =
        posts;

    if (selectedStatFilter ==
        'near') {
      basePosts = posts.where(
        (post) {
          final s =
              getDeadlineStatus(
            post.closingDate,
          );

          return s ==
                  DeadlineStatus
                      .urgent ||
              s ==
                  DeadlineStatus
                      .near;
        },
      ).toList();
    }

    if (selectedStatFilter ==
        'new') {
      basePosts = posts.where(
        (post) {
          return post.status ==
              'new';
        },
      ).toList();
    }

    if (selectedStatFilter ==
        'bidding') {
      basePosts = posts.where(
        (post) {
          return post.isBiddingDoc &&
              !post.isDone;
        },
      ).toList();
    }

    if (selectedStatFilter ==
        'done') {
      basePosts = posts.where(
        (post) {
          return post.isDone;
        },
      ).toList();
    }

    if (keyword.isEmpty) {
      return basePosts;
    }

    return basePosts.where(
      (post) {
        final searchableText =
            '''
${post.lgu}
${post.title}
${post.referenceNumber}
${post.procuringEntity}
${post.areaOfDelivery}
${post.deliveryPeriod}
${post.classification}
${post.postingDate}
${post.closingDate}
${post.url}
${post.abc}
'''
                .toLowerCase();

        return searchableText
            .contains(
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

    Future.microtask(
      () {
        loadSavedData();
        loadPostsFromSupabase();
      },
    );
  }

  Future<void> loadSavedData() async {
    final prefs =
        await SharedPreferences.getInstance();

    if (!mounted) {
      return;
    }

    setState(() {
      keywordController.text =
          prefs.getString(
                'keywords',
              ) ??
              '';

      biddingDocsIds =
          (prefs.getStringList(
                    'bidding_docs_ids',
                  ) ??
                  [])
              .toSet();
    });
  }

  Future<void> saveData() async {
    final prefs =
        await SharedPreferences.getInstance();

    await prefs.setString(
      'keywords',
      keywordController.text,
    );
  }

  // ---------------------------------------------------------
  // LOAD ALL SUPABASE POSTS
  // ---------------------------------------------------------

  Future<
      List<
          Map<String, dynamic>>>
      fetchAllPhilgepsPosts() async {
    const int pageSize =
        1000;

    int from = 0;

    final List<
            Map<String, dynamic>>
        allRows = [];

    while (true) {
      final response =
          await SupabaseConfig
              .client
              .from(
                'philgeps_posts',
              )
              .select()
              .order(
                'closing_date',
                ascending: true,
              )
              .order(
                'id',
                ascending: true,
              )
              .range(
                from,
                from +
                    pageSize -
                    1,
              );

      final List<
              Map<String, dynamic>>
          currentPage =
          List<
              Map<String, dynamic>>.from(
        response,
      );

      allRows.addAll(
        currentPage,
      );

      // If fewer than 1000 records were returned,
      // this is the final page.
      if (currentPage.length <
          pageSize) {
        break;
      }

      from += pageSize;
    }

    return allRows;
  }

  Future<void>
      loadPostsFromSupabase() async {
    try {
      final List<
              Map<String, dynamic>>
          response =
          await fetchAllPhilgepsPosts();

      // ProjectPost.fromJson now also reads:
      // is_bidding_doc
      // is_done
      // done_at
      final List<ProjectPost>
          items = response
              .map(
                ProjectPost
                    .fromJson,
              )
              .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        posts = items;

        sortByDeadline();

        statusMessage =
            'Loaded all ${posts.length} post(s) from Supabase.';
      });

      _filterChanges.value++;
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage =
            'Failed to load posts from Supabase: $e';
      });
    }
  }

  // ---------------------------------------------------------
  // CHECK PHILGEPS
  // ---------------------------------------------------------

  Future<void> checkPhilgeps() async {
    if (isLoading) {
      return;
    }

    setState(() {
      isLoading = true;

      statusMessage =
          'Checking PhilGEPS through Railway...';
    });

    try {
      final response =
          await http
              .post(
                Uri.parse(
                  apiUrl,
                ),
                headers: {
                  'Content-Type':
                      'application/json',
                },
                body:
                    jsonEncode(
                  {
                    'lgus':
                        lguList,
                    'keywords':
                        keywordController
                            .text
                            .trim(),
                  },
                ),
              )
              .timeout(
                const Duration(
                  minutes: 22,
                ),
              );

      if (!mounted) {
        return;
      }

      if (response.statusCode ==
          200) {
        final Map<String, dynamic>
            data =
            jsonDecode(
                  response.body,
                )
                as Map<
                    String,
                    dynamic>;

        final bool busy =
            data['busy'] == true;

        final int checked =
            (data['checked']
                        as num?)
                    ?.toInt() ??
                0;

        final int totalStored =
            (data['totalStored']
                        as num?)
                    ?.toInt() ??
                0;

        final List<dynamic>
            items =
            data['items']
                    is List
                ? data['items']
                    as List<
                        dynamic>
                : [];

        final loadedPosts =
            items
                .whereType<
                    Map<
                        String,
                        dynamic>>()
                .map(
                  ProjectPost
                      .fromJson,
                )
                .toList();

        setState(() {
          posts = loadedPosts;

          sortByDeadline();

          if (busy) {
            statusMessage =
                'Checker is still running. Showing $totalStored stored post(s).';
          } else if (checked >
              0) {
            statusMessage =
                'Check completed. $checked new post(s) processed. '
                '${posts.length} total active post(s).';
          } else {
            statusMessage =
                'Check completed. No new post found. '
                '${posts.length} active post(s) stored.';
          }
        });

        _filterChanges.value++;
      } else {
        String errorMessage =
            'Railway error: ${response.statusCode}';

        try {
          final data =
              jsonDecode(
            response.body,
          );

          if (data
                  is Map<
                      String,
                      dynamic> &&
              data['error']
                      ?.toString()
                      .isNotEmpty ==
                  true) {
            errorMessage =
                data['error']
                    .toString();
          }
        } catch (_) {}

        setState(() {
          statusMessage =
              errorMessage;
        });
      }
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage =
            'The checker is taking longer than expected. '
            'It may still be running in Railway.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage =
            'Cannot connect to Railway backend: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------
  // SORTING
  // ---------------------------------------------------------

  void sortByDeadline() {
    posts.sort(
      (a, b) {
        final aIsNew =
            a.status == 'new';

        final bIsNew =
            b.status == 'new';

        if (aIsNew &&
            !bIsNew) {
          return -1;
        }

        if (!aIsNew &&
            bIsNew) {
          return 1;
        }

        final aPosted =
            _parseDate(
          a.postingDate,
        );

        final bPosted =
            _parseDate(
          b.postingDate,
        );

        if (aPosted == null &&
            bPosted == null) {
          return 0;
        }

        if (aPosted == null) {
          return 1;
        }

        if (bPosted == null) {
          return -1;
        }

        return bPosted
            .compareTo(
          aPosted,
        );
      },
    );
  }

  bool isNewPost(
    ProjectPost post,
  ) {
    final posted =
        _parseDate(
      post.postingDate,
    );

    if (posted == null) {
      return false;
    }

    final postedPH =
        posted.toLocal();

    final ageHours =
        DateTime.now()
            .difference(
              postedPH,
            )
            .inHours;

    return ageHours < 24;
  }

  // ---------------------------------------------------------
  // DEADLINE HELPERS
  // ---------------------------------------------------------

  DeadlineStatus getDeadlineStatus(
    String dateText,
  ) {
    final date =
        _parseDate(
      dateText,
    );

    if (date == null) {
      return DeadlineStatus
          .unknown;
    }

    final diff =
        date.difference(
      DateTime.now(),
    );

    if (diff.isNegative) {
      return DeadlineStatus
          .closed;
    }

    if (diff.inHours <= 24) {
      return DeadlineStatus
          .urgent;
    }

    if (diff.inHours <= 72) {
      return DeadlineStatus
          .near;
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
    final date =
        _parseDate(
      dateText,
    );

    if (date == null) {
      return 'No closing date';
    }

    final diff =
        date.difference(
      DateTime.now(),
    );

    if (diff.isNegative) {
      return 'Closed';
    }

    final days =
        diff.inDays;

    final hours =
        diff.inHours % 24;

    final minutes =
        diff.inMinutes % 60;

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
    return _formattedDates
        .putIfAbsent(
      dateText,
      () {
        final date =
            _parseDate(
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
      backgroundColor:
          _DashboardColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
            context,
            constraints,
          ) {
            final isWide =
                constraints.maxWidth >=
                    850;

            final pagePadding =
                isWide
                    ? 24.0
                    : 16.0;

            final horizontal =
                constraints.maxWidth >
                        maxWidth +
                            pagePadding *
                                2
                    ? (constraints
                                .maxWidth -
                            maxWidth) /
                        2
                    : pagePadding;

            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding:
                      EdgeInsets
                          .fromLTRB(
                    horizontal,
                    pagePadding,
                    horizontal,
                    20,
                  ),
                  sliver:
                      SliverToBoxAdapter(
                    child:
                        buildHero(
                      isWide,
                    ),
                  ),
                ),
                SliverPadding(
                  padding:
                      EdgeInsets
                          .fromLTRB(
                    horizontal,
                    0,
                    horizontal,
                    pagePadding,
                  ),
                  sliver:
                      DecoratedSliver(
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFFCFDFC,
                      ),
                      border:
                          Border.all(
                        color:
                            const Color(
                          0xFFE5E7EB,
                        ),
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        18,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors
                                  .black
                                  .withValues(
                            alpha:
                                0.025,
                          ),
                          blurRadius:
                              16,
                          offset:
                              const Offset(
                            0,
                            4,
                          ),
                        ),
                      ],
                    ),
                    sliver:
                        SliverPadding(
                      padding:
                          EdgeInsets.all(
                        isWide
                            ? 24
                            : 20,
                      ),
                      sliver:
                          ValueListenableBuilder<
                              int>(
                        valueListenable:
                            _filterChanges,

                        // Filter changes reuse the search subtree
                        // and leave the header alone.
                        child:
                            buildFilterSection(),

                        builder: (
                          context,
                          _,
                          search,
                        ) {
                          final visiblePosts =
                              filteredPosts;

                          return SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child:
                                    Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .stretch,
                                  children: [
                                    buildStats(
                                      isWide,
                                    ),
                                    const SizedBox(
                                      height:
                                          20,
                                    ),
                                    search!,
                                    buildStatusMessage(
                                      visiblePosts
                                          .length,
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