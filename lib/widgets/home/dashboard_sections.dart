part of '../../main.dart';

extension _DashboardSections on _HomePageState {
  String toTitleCase(String value) {
    return value.split('-').map((part) {
      return part.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1);
      }).join(' ');
    }).join('-');
  }

  Widget _checkButton() => ElevatedButton.icon(
        onPressed: isLoading ? null : checkPhilgeps,
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _DashboardColors.green))
            : const Icon(Icons.refresh_rounded, size: 18),
        label: Text(isLoading ? 'Checking…' : 'Check Updates'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _DashboardColors.gold,
          foregroundColor: _DashboardColors.green,
          disabledBackgroundColor: const Color(0xFFF1DE97),
          disabledForegroundColor: _DashboardColors.green,
          minimumSize: const Size(0, 44),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );

  Widget buildHero(bool isWide) {
    final title =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('PhilGEPS Notif & Alert',
          style: TextStyle(
              color: Colors.white,
              fontSize: isWide ? 28 : 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5)),
      const SizedBox(height: 6),
      const Text('Procurement Monitoring & Bid Deadline Dashboard',
          style:
              TextStyle(color: Color(0xFFD5E7DE), fontSize: 13, height: 1.5)),
    ]);
    final live = Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
              color: Color(0xFF96D5AD), shape: BoxShape.circle)),
      const SizedBox(width: 7),
      const Text('LIVE MONITOR',
          style: TextStyle(
              color: Color(0xFFD5E7DE),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1)),
    ]);
    return Container(
      padding: EdgeInsets.all(isWide ? 24 : 20),
      decoration: BoxDecoration(
          color: _DashboardColors.green,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: _DashboardColors.green.withValues(alpha: .12),
                blurRadius: 16,
                offset: const Offset(0, 4))
          ]),
      child: isWide
          ? Row(children: [
              Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      border:
                          Border.all(color: Colors.white.withValues(alpha: .2)),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.account_balance_outlined,
                      color: _DashboardColors.gold, size: 25)),
              const SizedBox(width: 16),
              Expanded(child: title),
              const SizedBox(width: 16),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [live, const SizedBox(height: 10), _checkButton()]),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              title,
              const SizedBox(height: 16),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [live, _checkButton()]),
            ]),
    );
  }

  Widget buildStats(bool isWide) {
    final definitions = [
      (
        'all',
        'Total Opportunities',
        posts.length,
        Icons.layers_outlined,
        _DashboardColors.green,
        'All monitored postings'
      ),
      (
        'near',
        'Near Deadline',
        urgentCount,
        Icons.schedule_outlined,
        _DashboardColors.orange,
        'Closing within 72 hours'
      ),
      (
        'new',
        'New Posts',
        newCount,
        Icons.auto_awesome_outlined,
        _DashboardColors.goldText,
        'Recently flagged as new'
      ),
      (
        'bidding',
        'Bidding Documents',
        biddingDocsCount,
        Icons.folder_outlined,
        _DashboardColors.secondary,
        'Selected for preparation'
      ),
    ];
    const messages = {
      'all': 'Showing all PhilGEPS posts.',
      'near': 'Showing near deadline posts only.',
      'new': 'Showing new PhilGEPS posts only.',
      'bidding': 'Showing selected bidding documents.'
    };
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 340
              ? 2
              : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final item in definitions)
          SizedBox(
              width: width,
              child: _DashboardSurface(
                selected: selectedStatFilter == item.$1,
                accent: item.$5,
                padding: const EdgeInsets.all(16),
                onTap: () => _updateState(() {
                  selectedStatFilter = item.$1;
                  statusMessage = messages[item.$1]!;
                }),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(item.$2,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _DashboardColors.muted,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(width: 4),
                        Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                                color: item.$5.withValues(alpha: .09),
                                borderRadius: BorderRadius.circular(8)),
                            child: Icon(item.$4, size: 17, color: item.$5))
                      ]),
                      const SizedBox(height: 8),
                      Text('${item.$3}',
                          style: const TextStyle(
                              fontSize: 30,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                              color: _DashboardColors.ink,
                              letterSpacing: -.7)),
                      const SizedBox(height: 6),
                      Text(item.$6,
                          style: const TextStyle(
                              fontSize: 11, color: _DashboardColors.muted)),
                    ]),
              )),
      ]);
    });
  }

  Widget buildFilterSection() => _DashboardSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.tune_rounded, size: 18, color: _DashboardColors.green),
          SizedBox(width: 8),
          Text('Search Opportunities',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _DashboardColors.ink))
        ]),
        const SizedBox(height: 4),
        const Text(
            'Find a project by title, LGU, reference number, entity, or delivery area.',
            style: TextStyle(fontSize: 12, color: _DashboardColors.muted)),
        const SizedBox(height: 12),
        TextField(
          controller: keywordController,
          maxLines: 1,
          style: const TextStyle(fontSize: 14, color: _DashboardColors.ink),
          onChanged: (_) {
            saveData();
            _updateState(() {});
          },
          decoration: InputDecoration(
            hintText:
                'Search project title, LGU, reference no., procuring entity…',
            hintStyle:
                const TextStyle(fontSize: 13, color: _DashboardColors.muted),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 21, color: _DashboardColors.muted),
            suffixIcon: keywordController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      keywordController.clear();
                      saveData();
                      _updateState(() {});
                    }),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            filled: true,
            fillColor: const Color(0xFFFAFBFA),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _DashboardColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: _DashboardColors.secondary, width: 1.5)),
          ),
        ),
      ]));

  String get _activeFilterLabel => switch (selectedStatFilter) {
        'near' => 'Near Deadline',
        'new' => 'New Posts',
        'bidding' => 'Bidding Documents',
        _ => 'All Opportunities',
      };

  Widget buildStatusMessage() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Showing:',
                    style:
                        TextStyle(fontSize: 12, color: _DashboardColors.muted)),
                _StatusBadge(_activeFilterLabel),
                if (keywordController.text.trim().isNotEmpty)
                  Text('Search: “${keywordController.text.trim()}”',
                      style: const TextStyle(
                          fontSize: 12, color: _DashboardColors.ink)),
                Text('${filteredPosts.length} results',
                    style: const TextStyle(
                        fontSize: 12, color: _DashboardColors.muted)),
              ]),
          if (!statusMessage.startsWith('Showing ')) ...[
            const SizedBox(height: 8),
            Semantics(
                liveRegion: true,
                child: Text(statusMessage,
                    style: const TextStyle(
                        fontSize: 12,
                        color: _DashboardColors.muted,
                        height: 1.4))),
          ],
        ]),
      );

  Widget _postActions(ProjectPost post) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (post.isBiddingDoc) ...[
          IconButton(
              tooltip: 'Open Bid Docs PDF Editor',
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
              style: IconButton.styleFrom(
                  foregroundColor: _DashboardColors.goldText,
                  backgroundColor: const Color(0xFFFFF8DF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PdfEditorScreen(
                              province: post.areaOfDelivery.trim().isNotEmpty
                                  ? post.areaOfDelivery.trim()
                                  : 'Bukidnon',
                              municipality: toTitleCase(post.lgu.trim()),
                              projectTitle: post.title.trim(),
                              referenceNumber: post.referenceNumber.trim(),
                              procuringEntity: post.procuringEntity.trim(),
                              deliveryPeriod: post.deliveryPeriod.trim(),
                              date: DateFormat('MMMM d, yyyy')
                                  .format(DateTime.now()),
                              bidderName: 'MIKATA PRIME CORPORATION',
                            )));
              }),
          const SizedBox(width: 8),
        ],
        IconButton(
          tooltip: isInBiddingDocs(post)
              ? 'Remove from Bidding Docs'
              : 'Add to Bidding Docs',
          isSelected: isInBiddingDocs(post),
          onPressed: () => toggleBiddingDocs(post),
          icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
          selectedIcon: const Icon(Icons.thumb_up_alt_rounded, size: 18),
          style: IconButton.styleFrom(
            foregroundColor: _DashboardColors.green,
            backgroundColor: const Color(0xFFF1F7F3),
            side: const BorderSide(color: Color(0xFFCCE0D5)),
            highlightColor: const Color(0xFFD9EADF),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? _DashboardColors.green
                    : const Color(0xFFF1F7F3)),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? Colors.white
                    : _DashboardColors.green),
          ),
        ),
      ]);

  Widget buildPostCard(ProjectPost post) {
    final deadlineStatus = getDeadlineStatus(post.closingDate);
    final statusColor = switch (deadlineStatus) {
      DeadlineStatus.urgent || DeadlineStatus.closed => _DashboardColors.danger,
      DeadlineStatus.near => _DashboardColors.orange,
      DeadlineStatus.safe => _DashboardColors.secondary,
      _ => _DashboardColors.muted,
    };
    final countdown = getCountdown(post.closingDate);
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _DashboardSurface(
          onTap: () => openPhilgepsLink(post.url),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                _StatusBadge(post.status == 'new' ? 'NEW' : 'OLD',
                    color: post.status == 'new'
                        ? _DashboardColors.goldText
                        : _DashboardColors.muted),
                _StatusBadge(
                    deadlineStatus == DeadlineStatus.closed
                        ? 'Closed'
                        : deadlineStatus == DeadlineStatus.unknown
                            ? countdown
                            : 'Closes in $countdown',
                    color: statusColor,
                    icon: Icons.schedule_rounded),
                if (post.isBiddingDoc) const _StatusBadge('Bidding document'),
              ])),
              const SizedBox(width: 12),
              _postActions(post),
            ]),
            const SizedBox(height: 12),
            Tooltip(
                message: post.title,
                child: Text(post.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: _DashboardColors.ink))),
            const SizedBox(height: 6),
            Text(post.procuringEntity,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: _DashboardColors.muted)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _StatusBadge(toTitleCase(post.lgu),
                  color: _DashboardColors.muted,
                  icon: Icons.location_city_outlined),
              _StatusBadge(post.classification, color: _DashboardColors.muted),
              _StatusBadge(post.areaOfDelivery,
                  color: _DashboardColors.muted, icon: Icons.place_outlined),
            ]),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: _DashboardColors.border)),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 300
                      ? 2
                      : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              final fields = [
                _OpportunityDatum('Reference No.', post.referenceNumber,
                    monospace: true),
                _OpportunityDatum(
                    post.budgetType, '₱${abcFormatter.format(post.abc)}',
                    emphasized: true, color: _DashboardColors.green),
                _OpportunityDatum('Posted', formatDate(post.postingDate)),
                _OpportunityDatum('Closing', formatDate(post.closingDate),
                    color: statusColor),
              ];
              return Wrap(spacing: 16, runSpacing: 16, children: [
                for (final field in fields) SizedBox(width: width, child: field)
              ]);
            }),
            const SizedBox(height: 10),
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => openPhilgepsLink(post.url),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('View PhilGEPS'),
                  style: TextButton.styleFrom(
                      foregroundColor: _DashboardColors.green,
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                )),
          ]),
        ));
  }

  Widget _emptyState() {
    final keyword = keywordController.text.trim().isNotEmpty;
    final bidding = selectedStatFilter == 'bidding' && !keyword;
    final noPosts = posts.isEmpty && !isLoading;
    final title = bidding
        ? 'No bidding documents selected yet'
        : keyword
            ? 'No opportunities found'
            : selectedStatFilter == 'near'
                ? 'No approaching deadlines'
                : selectedStatFilter == 'new'
                    ? 'No new posts'
                    : 'No opportunities yet';
    final description = bidding
        ? 'Tap the thumbs-up icon on an opportunity to save it here.'
        : keyword
            ? 'Try another keyword or filter.'
            : noPosts
                ? 'Check for updates to load the latest PhilGEPS postings.'
                : 'Choose another filter to explore your monitored opportunities.';
    return _DashboardSurface(
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Icon(
                  bidding
                      ? Icons.folder_open_outlined
                      : Icons.search_off_rounded,
                  size: 32,
                  color: _DashboardColors.muted),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _DashboardColors.ink)),
              const SizedBox(height: 6),
              Text(description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      color: _DashboardColors.muted,
                      height: 1.5)),
              if (noPosts && !bidding && !keyword) ...[
                const SizedBox(height: 16),
                _checkButton()
              ],
            ])));
  }

  Widget buildDashboard() {
    final visiblePosts = filteredPosts;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        const heading =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Opportunities',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _DashboardColors.ink)),
          SizedBox(height: 4),
          Text('Track active PhilGEPS procurement postings',
              style: TextStyle(fontSize: 12, color: _DashboardColors.muted)),
        ]);
        const sort = Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sort_rounded, size: 16, color: _DashboardColors.muted),
          SizedBox(width: 6),
          Text('New first · Latest posted',
              style: TextStyle(fontSize: 12, color: _DashboardColors.muted))
        ]);
        return constraints.maxWidth >= 650
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [heading, sort])
            : const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, SizedBox(height: 10), sort]);
      }),
      const SizedBox(height: 16),
      AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: _DashboardLoading())
              : const SizedBox.shrink()),
      if (visiblePosts.isEmpty && !isLoading)
        _emptyState()
      else
        ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visiblePosts.length,
            itemBuilder: (context, index) =>
                buildPostCard(visiblePosts[index])),
    ]);
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();
  @override
  Widget build(BuildContext context) => const _DashboardSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Checking PhilGEPS opportunities…',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _DashboardColors.green)),
        SizedBox(height: 12),
        LinearProgressIndicator(
            minHeight: 3,
            color: _DashboardColors.secondary,
            backgroundColor: Color(0xFFEEF7F2)),
      ]));
}
