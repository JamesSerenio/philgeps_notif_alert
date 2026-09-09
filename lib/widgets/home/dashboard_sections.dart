part of '../../main.dart';

extension _DashboardSections on _HomePageState {
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
        duration: const Duration(milliseconds: 120),
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
              _updateState(() {});
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
          _updateState(() {
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
          _updateState(() {
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
          _updateState(() {
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
          _updateState(() {
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
      onTap: () => openPhilgepsLink(post.url),
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
                  '${post.budgetType}: ${abcFormatter.format(post.abc)}',
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (post.isBiddingDoc) ...[
                  InkWell(
                    onTap: () {
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
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppStyles.gold,
                        ),
                      ),
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 16,
                        color: AppStyles.gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                InkWell(
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
              ],
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
            Builder(
              builder: (context) {
                final visiblePosts = filteredPosts;

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visiblePosts.length,
                  itemBuilder: (context, index) {
                    return buildPostCard(visiblePosts[index]);
                  },
                );
              },
            ),
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
}
