import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/utils/post_dates.dart';

void main() {
  final now = DateTime.parse('2026-11-08T05:48:00+08:00');
  test('NEW expires after exactly 24 elapsed hours without resetting discovery',
      () {
    expect(discoveredWithin24Hours(now, now: now), isTrue);
    expect(
        discoveredWithin24Hours(now.subtract(const Duration(hours: 24)),
            now: now),
        isFalse);
    expect(
        discoveredWithin24Hours(now.add(const Duration(seconds: 1)), now: now),
        isFalse);
    expect(discoveredWithin24Hours(null, now: now), isFalse);
  });
  test(
      'PH wall times match explicit timestamptz offsets independent of device timezone',
      () {
    expect(parsePhilgepsDate('2026-11-08 05:48:00'), now.toUtc());
    expect(parsePhilgepsDate('2026-11-07T21:48:00Z'), now.toUtc());
    expect(parsePhilgepsDate('2026-11-08T05:48:00+08:00'), now.toUtc());
    expect(philippineTime(now).hour, 5);
  });
  test('all eight Railway candidates were first discovered before November 8',
      () {
    const discoveries = {
      '13306152': '2026-10-23T17:00:57.781409+00:00',
      '13306135': '2026-10-23T17:00:59.247626+00:00',
      '13315332': '2026-10-28T18:31:25.897619+00:00',
      '13278266': '2026-10-08T20:31:25.693081+00:00',
      '13292869': '2026-10-18T18:00:57.505599+00:00',
      '13300031': '2026-10-20T18:30:58.867645+00:00',
      '13321123': '2026-10-30T18:31:19.257721+00:00',
      '13321142': '2026-10-30T18:31:21.307638+00:00',
    };
    for (final entry in discoveries.entries) {
      expect(discoveredWithin24Hours(parsePhilgepsDate(entry.value), now: now),
          isFalse,
          reason: entry.key);
    }
  });
}
