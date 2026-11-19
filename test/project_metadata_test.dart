import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:philgeps_notif_alert/main.dart';
import 'package:philgeps_notif_alert/utils/post_dates.dart';

void main() {
  test('closed BDocs hide at the deadline without modifying the selection', () {
    final row = {
      'id': 'saved-id',
      'is_bidding_doc': true,
      'manual_deadline': '2026-11-19',
      'closing_date': '2026-12-01T00:00:00Z'
    };
    final post = ProjectPost.fromJson(row);
    expect(
        post.isClosedForBidding(
            now: DateTime.parse('2026-11-19T23:59:59+08:00')),
        isFalse);
    expect(
        post.isClosedForBidding(
            now: DateTime.parse('2026-11-20T00:00:00+08:00')),
        isTrue);
    expect(post.isBiddingDoc, isTrue);
    expect(post.id, 'saved-id');
    final official =
        ProjectPost.fromJson({'closing_date': '2026-11-19T10:00:00+08:00'});
    expect(
        official.isClosedForBidding(
            now: DateTime.parse('2026-11-19T09:59:59+08:00')),
        isFalse);
    expect(
        official.isClosedForBidding(
            now: DateTime.parse('2026-11-19T10:00:00+08:00')),
        isTrue);
    expect(ProjectPost.fromJson({'status': ' CLOSED '}).isClosedForBidding(),
        isTrue);
    expect(
        ProjectPost.fromJson({'closing_date': 'unknown'}).isClosedForBidding(),
        isFalse);
    expect(ProjectPost.fromJson({}).isClosedForBidding(), isFalse);
  });
  testWidgets(
      'normal dashboard reload shows the saved shared row on its original card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    var saved = false;
    final row = <String, dynamic>{
      'id': 'fc066763-84a8-4423-bbd8-eada9101c201',
      'is_bidding_doc': true,
      'is_manual': true,
      'title': '',
      'reference_number': '',
      'procuring_entity': '',
      'lgu': '',
      'abc': null,
    };
    http.Client client() => MockClient((request) async {
          final data = request.url.path.endsWith('/philgeps_posts')
              ? [
                  {
                    ...row,
                    if (saved) ...{
                      'title':
                          'SUPPLY AND DELIVERY OF WATER METER AND FITTINGS',
                      'reference_number': '132124',
                      'procuring_entity': 'MUNICIPALITY OF SUMILAO, BUKIDNON',
                      'lgu': 'SUMILAO',
                      'area_of_delivery': 'BUKIDNON',
                      'manual_deadline': '2026-11-19',
                    }
                  }
                ]
              : request.url.path.endsWith('/check/last-success')
                  ? <String, dynamic>{}
                  : [];
          return http.Response(jsonEncode(data), 200,
              headers: {'content-type': 'application/json'}, request: request);
        });
    await http.runWithClient(() async {
      await Supabase.initialize(
          url: 'https://metadata-test.invalid',
          publishableKey: 'test',
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false, detectSessionInUri: false),
          httpClient: client());
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(HomePage));
        await tester.runAsync(() async => state.loadPostsFromSupabase());
        await tester.pumpAndSettle();
        expect(find.text('Untitled Project'), findsOneWidget,
            reason: 'Rows: ${state.posts.length}; ${state.statusMessage}');
        saved = true;
        await tester.runAsync(() async => state.loadPostsFromSupabase());
        await tester.pumpAndSettle();
        expect(find.text('SUPPLY AND DELIVERY OF WATER METER AND FITTINGS'),
            findsOneWidget);
        expect(find.text('MUNICIPALITY OF SUMILAO, BUKIDNON'), findsOneWidget);
        expect(find.text('132124'), findsOneWidget);
        expect(find.text('Not available'), findsOneWidget);
        expect(find.text('Nov 19, 2026'), findsOneWidget);
        expect(state.posts.single.id, row['id']);
        expect(state.posts.single.isBiddingDoc, isTrue);
        expect(state.posts.single.areaOfDelivery, 'BUKIDNON');
        expect(state.posts.single.lgu, 'SUMILAO');
        // Filtering BDocs hides expired cards without deleting the shared row.
        state.setState(() {
          state.posts = <ProjectPost>[
            ProjectPost.fromJson({
              ...row,
              'title': 'Closed saved bid',
              'manual_deadline': '2000-01-01'
            }),
            ProjectPost.fromJson({
              ...row,
              'id': 'future',
              'title': 'Open saved bid',
              'manual_deadline': '2100-01-01'
            }),
            ProjectPost.fromJson(
                {...row, 'id': 'no-deadline', 'title': 'Blank deadline bid'}),
          ];
          state.selectedStatFilter = 'bidding';
        });
        // Normal filter invalidation is raised by refresh/stat taps.
        await tester.pumpAndSettle();
        expect(state.biddingDocsCount, 2);
        expect(state.filteredPosts.map((post) => post.id),
            ['future', 'no-deadline']);
        expect(state.posts.length, 3);
        expect(state.posts.first.isBiddingDoc, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await Supabase.instance.client.realtime.disconnect();
          await Supabase.instance.dispose();
        });
        await tester.pump(const Duration(seconds: 2));
      }
    }, client);
  });
  test('shared metadata, manual deadline and null budget retain their meaning',
      () {
    final project = ProjectPost.fromJson({
      'id': 'fc066763-84a8-4423-bbd8-eada9101c201',
      'title': 'SUPPLY AND DELIVERY OF WATER METER AND FITTINGS',
      'reference_number': '132124',
      'procuring_entity': 'MUNICIPALITY OF SUMILAO, BUKIDNON',
      'lgu': 'SUMILAO',
      'area_of_delivery': 'BUKIDNON',
      'manual_deadline': '2026-11-19',
      'closing_date': '2026-11-20T01:00:00Z',
      'posting_date': null,
      'abc': null,
      'is_bidding_doc': true,
    });
    expect(project.referenceNumber, '132124');
    expect(project.closingDate, '2026-11-19');
    expect(project.postingDate, isEmpty,
        reason: 'Document date must not become publication date');
    expect(project.abc, isNull);
    expect(project.copyWith(isDone: true).abc, isNull);
    expect(project.copyWith(isDone: true).id, project.id);
    expect(parsePhilgepsDeadline(project.closingDate),
        DateTime.parse('2026-11-19T15:59:59.999999Z'));
  });
  test('blank and older projects have safe fallbacks; real zero remains zero',
      () {
    expect(
        ProjectPost.fromJson({'id': 'blank'}).displayTitle, 'Untitled Project');
    expect(ProjectPost.fromJson({'id': 'zero', 'abc': 0}).abc, 0);
    final older = ProjectPost.fromJson({
      'title': '',
      'projectTitle': 'Older project',
      'referenceNumber': '123',
      'procuringEntity': 'Agency',
      'municipality': 'Sumilao',
      'province': 'Bukidnon',
      'closing_date': '2026-11-19T01:00:00Z'
    });
    expect(older.title, 'Older project');
    expect(older.lgu, 'Sumilao');
    expect(older.closingDate, '2026-11-19T01:00:00Z');
  });
}
