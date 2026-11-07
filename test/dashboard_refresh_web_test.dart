@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:philgeps_notif_alert/main.dart';

void main() {
  final rows = <Map<String, dynamic>>[];
  final requests = <Uri>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://dashboard-test.invalid',
      publishableKey: 'test',
      authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false, detectSessionInUri: false),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/philgeps_posts')) {
          final offset =
              int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
          final limit =
              int.tryParse(request.url.queryParameters['limit'] ?? '1000') ??
                  1000;
          return http.Response(
              jsonEncode(rows.skip(offset).take(limit).toList()), 200,
              request: request, headers: {'content-type': 'application/json'});
        }
        return http.Response('[]', 200,
            request: request, headers: {'content-type': 'application/json'});
      }),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
  });
  testWidgets(
      'dashboard refresh uses discovery, retains old posts and saved decisions, and pages through all rows',
      (tester) async {
    final now = DateTime.now().toUtc();
    rows.addAll(List.generate(
        1001,
        (i) => {
              'id': 'old-$i',
              'reference_number': '$i',
              'title': 'Old post $i',
              'created_at':
                  now.subtract(const Duration(days: 10)).toIso8601String(),
              'posting_date':
                  now.subtract(const Duration(days: 10)).toIso8601String(),
              'closing_date':
                  now.add(const Duration(days: 2)).toIso8601String(),
              'status': 'new',
              'lgu': 'LGU SUMILAO',
              'is_bidding_doc': i == 0,
            }));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(HomePage));
    await tester.runAsync(() async {
      await state.loadPostsFromSupabase();
    });
    await tester.pumpAndSettle();
    expect(state.posts.length, 1001, reason: state.statusMessage);
    expect(state.newCount, 0);
    expect(
        requests.any((uri) => uri.queryParameters['offset'] == '1000'), isTrue);
    expect(
        requests.first.queryParameters['order']!.replaceAll('.nullslast', ''),
        'created_at.desc,id.desc');
    rows.insert(0, {
      'id': 'discovered',
      'reference_number': 'new-reference',
      'title': 'New discovery',
      'created_at': now.toIso8601String(),
      'posting_date': '2026-01-01T00:00:00Z',
      'closing_date': now.add(const Duration(days: 2)).toIso8601String(),
      'status': 'old',
      'lgu': 'SUMILAO',
    });
    final beforeAutomatic = requests.length;
    await tester.pump(const Duration(seconds: 61));
    expect(requests.length, greaterThan(beforeAutomatic));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await state.loadPostsFromSupabase();
    });
    await tester.pumpAndSettle();
    expect(state.posts.length, 1002, reason: state.statusMessage);
    expect(state.posts.first.id, 'discovered');
    expect(state.newCount, 1);
    state.selectedStatFilter = 'new';
    expect(state.filteredPosts.single.id, 'discovered');
    expect(
        state.getDeadlineStatus('2020-01-01T00:00:00Z'), DeadlineStatus.closed);
    state.selectedStatFilter = 'bidding';
    expect(state.filteredPosts.single.id, 'old-0');
    final before = requests.length;
    await tester.runAsync(() async {
      await Future.wait<void>([
        state.loadPostsFromSupabase(),
        state.loadPostsFromSupabase(),
      ]);
    });
    expect(requests.length - before,
        2); // One two-page refresh, not two refreshes.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
