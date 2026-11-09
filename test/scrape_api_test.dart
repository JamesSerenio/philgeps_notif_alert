import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philgeps_notif_alert/services/scrape_api.dart';

void main() {
  test(
      'starts actual scrape, keeps polling busy run, returns only after completion',
      () async {
    final requests = <http.Request>[];
    var polls = 0;
    final api = ScrapeApi(
        baseUrl: 'https://scraper.invalid',
        accessToken: () async => 'user-session',
        wait: (_) async {},
        client: MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Bearer user-session');
          if (request.method == 'POST') {
            return http.Response(
                jsonEncode({
                  'accepted': true,
                  'run': {'id': 'run', 'status': 'running'}
                }),
                202);
          }
          polls++;
          return http.Response(
              jsonEncode({
                'run': {
                  'id': 'run',
                  'status': polls == 3 ? 'completed' : 'running',
                  'newCount': 2
                },
                'lastSuccessAt': '2026-11-10T10:00:00Z'
              }),
              200);
        }));
    final result = await api.check();
    expect(requests.first.method, 'POST');
    expect(requests.first.url.path, '/check');
    expect(
        requests.skip(1).every((r) => r.url.path == '/check/status'), isTrue);
    expect(polls, 3);
    expect(result['run']['newCount'], 2);
    api.close();
  });

  test('joins an already-running scrape without posting a second request',
      () async {
    var starts = 0;
    final api = ScrapeApi(
        baseUrl: 'https://scraper.invalid',
        accessToken: () async => 'token',
        wait: (_) async {},
        client: MockClient((request) async {
          if (request.method == 'POST') starts++;
          return http.Response(
              jsonEncode({
                'accepted': false,
                'reason': 'running',
                'run': {
                  'id': 'existing',
                  'status': request.method == 'POST' ? 'running' : 'completed',
                  'newCount': 0
                }
              }),
              200);
        }));
    expect((await api.check())['run']['newCount'], 0);
    expect(starts, 1);
    api.close();
  });

  for (final code in [401, 403, 429, 503]) {
    test('HTTP $code fails without reporting completion', () async {
      final api = ScrapeApi(
          baseUrl: 'https://scraper.invalid',
          accessToken: () async => 'token',
          client: MockClient(
              (_) async => http.Response('{"error":"Denied"}', code)));
      await expectLater(api.check(), throwsA(isA<Exception>()));
      api.close();
    });
  }

  test('backend failure is surfaced after acceptance', () async {
    final api = ScrapeApi(
        baseUrl: 'https://scraper.invalid',
        accessToken: () async => 'token',
        client: MockClient((request) async => http.Response(
            jsonEncode({
              'run': {
                'id': 'run',
                'status': request.method == 'POST' ? 'running' : 'failed',
                'error': 'LGU unavailable'
              }
            }),
            200)));
    await expectLater(api.check(),
        throwsA(predicate((e) => e.toString().contains('LGU unavailable'))));
    api.close();
  });
}
