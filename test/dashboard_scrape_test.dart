import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:philgeps_notif_alert/main.dart';

void main() {
  testWidgets(
      'manual check waits for completion, refreshes posts, blocks duplicate clicks, and reports failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var starts = 0, reads = 0, discovered = false, fail = false;
    var newCount = 1;
    Completer<http.Response>? completion;
    final now = DateTime.now().toUtc();
    final row = <String, dynamic>{
      'id': 'opportunity',
      'reference_number': '123',
      'lgu': 'sumilao',
      'title': 'Monitored opportunity',
      'is_bidding_doc': true,
      'created_at': now.toIso8601String(),
      'posting_date': now.toIso8601String(),
      'closing_date': now.add(const Duration(days: 2)).toIso8601String(),
    };
    http.Response json(Object data, [int status = 200]) =>
        http.Response(jsonEncode(data), status,
            headers: {'content-type': 'application/json'});
    Future<http.Response> handle(http.Request request) async {
      final path = request.url.path;
      if (path.endsWith('/token')) {
        final payload = base64Url
            .encode(utf8.encode(jsonEncode({
              'sub': 'owner',
              'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
                  1000,
            })))
            .replaceAll('=', '');
        return json({
          'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
          'refresh_token': 'refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'owner',
            'email': 'owner@example.com',
            'aud': 'authenticated',
            'created_at': now.toIso8601String(),
            'app_metadata': {},
            'user_metadata': {}
          }
        });
      }
      if (path.endsWith('/philgeps_posts')) {
        reads++;
        return json(discovered ? [row] : []);
      }
      if (path.endsWith('/check/last-success'))
        return json({'lastSuccessAt': '2026-11-10T10:00:00Z'});
      if (path.endsWith('/check') && request.method == 'POST') {
        starts++;
        expect(request.headers['Authorization'], startsWith('Bearer '));
        if (fail) return json({'error': 'Scraper unavailable'}, 503);
        return json({
          'run': {'id': 'run', 'status': 'running'},
          'accepted': true
        }, 202);
      }
      if (path.endsWith('/check/status')) return completion!.future;
      return json([]);
    }

    http.Client mockClient() => MockClient((request) async {
          final response = await handle(request);
          return http.Response.bytes(response.bodyBytes, response.statusCode,
              headers: response.headers, request: request);
        });
    await http.runWithClient(() async {
      await Supabase.initialize(
          url: 'https://dashboard-test.invalid',
          publishableKey: 'test',
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false, detectSessionInUri: false),
          httpClient: mockClient());
      try {
        await Supabase.instance.client.auth
            .signInWithPassword(email: 'owner@example.com', password: 'test');
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();
        expect(starts, 0,
            reason: 'Opening the dashboard must not start a scrape.');
        final dynamic state = tester.state(find.byType(HomePage));
        final before = reads;
        completion = Completer<http.Response>();
        late Future<void> pending;
        await tester.runAsync(() async {
          pending = state.checkPhilgeps() as Future<void>;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await state.checkPhilgeps();
        });
        await tester.pump();
        expect(starts, 1);
        expect(find.text('Checking PhilGEPS...'), findsOneWidget);
        expect(state.isLoading, isTrue);
        expect(
            tester
                .widget<ElevatedButton>(find.byType(ElevatedButton).first)
                .onPressed,
            isNull);
        expect(reads, before,
            reason: 'Acceptance alone must not refresh or report success.');
        discovered = true;
        completion!.complete(json({
          'run': {'id': 'run', 'status': 'completed', 'newCount': newCount},
          'lastSuccessAt': '2026-11-10T10:00:00Z'
        }));
        await tester.runAsync(() async => pending);
        await tester.pumpAndSettle();
        expect(find.text('Updated successfully'), findsOneWidget,
            reason: state.statusMessage as String);
        expect(state.posts.length, 1);
        expect(state.biddingDocsCount, 1);
        expect(state.newCount, 1);
        expect(reads, greaterThan(before));
        expect(state.lastScrapeLabel, contains('06:00 PM'));
        expect(state.lastScrapeLabel, endsWith('PHT'));

        newCount = 0;
        completion = Completer<http.Response>()
          ..complete(json({
            'run': {'id': 'run', 'status': 'completed', 'newCount': newCount}
          }));
        await tester.runAsync(() async => state.checkPhilgeps());
        await tester.pumpAndSettle();
        expect(find.text('No new opportunities found'), findsOneWidget);
        fail = true;
        await tester.runAsync(() async => state.checkPhilgeps());
        await tester.pumpAndSettle();
        expect(find.text('Update failed \u2014 Retry'), findsOneWidget);
        expect(state.isLoading, isFalse);
        expect(state.posts.length, 1,
            reason: 'A failed scrape must preserve displayed records.');
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'The timestamp and button states must fit mobile.');
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await Supabase.instance.client.realtime.disconnect();
        });
        await Supabase.instance.dispose();
        await tester.pump(const Duration(seconds: 2));
      }
    }, mockClient);
  });
}
