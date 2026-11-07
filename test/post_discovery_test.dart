@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/main.dart';
import 'package:philgeps_notif_alert/utils/post_dates.dart';

void main() {
  final now = DateTime.parse('2026-11-08T05:48:00+08:00');
  test('NEW uses discovery, not posting date or a stale stored status', () {
    final post = ProjectPost.fromJson({
      'id': 'test',
      'created_at': '2026-11-07T21:30:00+00:00',
      'posting_date': '2026-10-01T00:00:00+00:00',
      'status': 'old',
      'is_bidding_doc': true,
    });
    expect(discoveredWithin24Hours(post.discoveredAt, now: now), isTrue);
    expect(post.copyWith(isDone: true).discoveredAt, post.discoveredAt);
    expect(post.copyWith(isDone: true).isBiddingDoc, isTrue);
    expect(
      discoveredWithin24Hours(
        parsePhilgepsDate('2026-10-30T18:31:19.257721+00:00'),
        now: now,
      ),
      isFalse,
    );
  });
  test('24 hour boundary, future and missing discovery timestamps', () {
    expect(discoveredWithin24Hours(now, now: now), isTrue);
    expect(
      discoveredWithin24Hours(
        now.subtract(const Duration(hours: 24)),
        now: now,
      ),
      isFalse,
    );
    expect(
      discoveredWithin24Hours(
        now.subtract(const Duration(hours: 24, microseconds: -1)),
        now: now,
      ),
      isTrue,
    );
    expect(
      discoveredWithin24Hours(now.add(const Duration(seconds: 1)), now: now),
      isFalse,
    );
    expect(discoveredWithin24Hours(null, now: now), isFalse);
  });
  test(
    'Philippine wall time and explicit UTC offsets describe the same instant',
    () {
      expect(parsePhilgepsDate('2026-11-08 05:48:00'), now.toUtc());
      expect(parsePhilgepsDate('2026-11-08T05:48:00+08:00'), now.toUtc());
      expect(parsePhilgepsDate('2026-11-07T21:48:00Z'), now.toUtc());
      expect(
        parsePhilgepsDate('2026-11-08'),
        DateTime.parse('2026-11-07T16:00:00Z'),
      );
      expect(philippineTime(now).hour, 5);
      expect(parsePhilgepsDate('invalid'), isNull);
    },
  );
}
