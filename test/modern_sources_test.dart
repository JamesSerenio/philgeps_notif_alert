import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:philgeps_notif_alert/main.dart';

void main() {
  test('source metadata and access status survive decision changes', () {
    final modern = ProjectPost.fromJson({
      'id': '-130491',
      'source': 'modern',
      'official_notice_id': '130491',
      'official_url':
          'https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491',
      'document_status': 'access_required',
      'is_bidding_doc': true,
    });
    final changed = modern.copyWith(isDone: true);
    expect(changed.sourceLabel, 'philgeps.gov.ph');
    expect(changed.sourceUrl, modern.url);
    expect(changed.documentLabel, 'Login / Access Required');
    expect(changed.officialNoticeId, '130491');
    expect(changed.isBiddingDoc, isTrue);
    final old = ProjectPost.fromJson({'id': '130491'});
    expect(old.sourceLabel, 'PhilGEPS');
    expect(old.sourceUrl, 'https://notices.philgeps.gov.ph/');
    expect(old.documentLabel, 'BDocs Not Verified');
  });

  testWidgets(
      'both sources search and filter; card and nested actions remain independent at all widths',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final launches = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      if (call.method == 'launch')
        launches.add((call.arguments as Map)['url'] as String);
      return true;
    });
    final rows = [
      {
        'id': '130491',
        'title': 'Existing CCTV supply',
        'reference_number': '130491',
        'procuring_entity': 'Existing Agency',
        'url': 'https://notices.philgeps.gov.ph/example',
        'lgu': 'sumilao',
        'closing_date': '2026-11-19T01:00:00Z'
      },
      {
        'id': '-130491',
        'source': 'modern',
        'title': 'Modern solar streetlights',
        'reference_number': '130491',
        'procuring_entity': 'MUNICIPALITY OF SUMILAO BUKIDNON',
        'url': 'https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491',
        'lgu': 'sumilao',
        'closing_date': '2026-11-19T01:00:00Z',
        'document_status': 'access_required'
      },
    ];
    http.Response json(Object value) => http.Response(jsonEncode(value), 200,
        headers: {'content-type': 'application/json'});
    http.Client client() => MockClient((request) async {
          final response = request.url.path.endsWith('/philgeps_posts')
              ? json(rows)
              : request.url.path.endsWith('/check/last-success')
                  ? json({'sources': []})
                  : json({'success': true});
          return http.Response.bytes(response.bodyBytes, response.statusCode,
              headers: response.headers, request: request);
        });
    await http.runWithClient(() async {
      await Supabase.initialize(
          url: 'https://sources-test.invalid',
          publishableKey: 'test',
          httpClient: client(),
          authOptions: const FlutterAuthClientOptions(
              autoRefreshToken: false, detectSessionInUri: false));
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1400, 1800);
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(HomePage));
        await tester.runAsync(() async => state.loadPostsFromSupabase());
        await tester.pumpAndSettle();
        expect(state.posts.length, 2, reason: state.statusMessage as String);
        for (final query in [
          '130491',
          'solar',
          'MUNICIPALITY OF SUMILAO',
          '2026-11-19'
        ]) {
          state.keywordController.text = query;
          expect((state.filteredPosts as List).any((p) => p.id == '-130491'),
              isTrue,
              reason: query);
        }
        state.keywordController.clear();
        state.closingFrom = DateTime(2026, 11, 19);
        state.closingTo = DateTime(2026, 11, 19);
        expect((state.filteredPosts as List).length, 2);
        state.closingFrom = DateTime(2026, 11, 20);
        expect(state.filteredPosts, isEmpty);
        state.closingFrom = null;
        state.closingTo = null;
        for (final width in [360.0, 768.0, 1400.0]) {
          tester.view.physicalSize = Size(width, 1800);
          state.setState(() {});
          await tester.pumpAndSettle();
          final modernCard = find.byKey(const ValueKey('notice-card:-130491'));
          await tester.scrollUntilVisible(modernCard, 400,
              scrollable: find.byType(Scrollable).first);
          await tester.pumpAndSettle();
          final source = find.descendant(
              of: modernCard,
              matching: find.widgetWithText(TextButton, 'philgeps.gov.ph'));
          await tester.ensureVisible(source);
          await tester.tap(source);
          await tester.pumpAndSettle();
          expect(launches.removeLast(),
              'https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491');
          expect(launches, isEmpty, reason: 'The label must launch only once.');
          final ink = find
              .descendant(of: modernCard, matching: find.byType(InkWell))
              .first;
          await tester.ensureVisible(ink);
          await tester.pumpAndSettle();
          await tester.tapAt(tester.getTopLeft(ink) + const Offset(3, 3));
          await tester.pumpAndSettle();
          expect(launches.removeLast(),
              'https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491');
          expect(tester.takeException(), isNull, reason: 'width $width');
          final access = find.descendant(of: modernCard,
              matching: find.widgetWithText(TextButton, 'Login / Access Required'));
          await tester.ensureVisible(access);
          await tester.tap(access);
          await tester.pumpAndSettle();
          expect(launches.removeLast(), 'https://philgeps.gov.ph/Indexes/viewLiveTenderDetails/130491');
          final thumb = find.descendant(of: modernCard,
              matching: find.byTooltip(width == 768 ? 'Remove from Bidding Docs' : 'Add to Bidding Docs'));
          await tester.ensureVisible(thumb);
          await tester.tap(thumb);
          await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pumpAndSettle();
          expect(launches, isEmpty, reason: 'BDocs selection must not open the card.');
          expect((state.posts as List).firstWhere((p) => p.id == '-130491').isBiddingDoc, width != 768);
        }
        final existingCard = find.byKey(const ValueKey('notice-card:130491'));
        await tester.ensureVisible(existingCard);
        final oldSource = find.descendant(
            of: existingCard,
            matching: find.widgetWithText(TextButton, 'PhilGEPS'));
        await tester.ensureVisible(oldSource);
        await tester.tap(oldSource);
        await tester.pumpAndSettle();
        expect(launches.removeLast(), 'https://notices.philgeps.gov.ph/');
        expect(
            tester
                .widget<InkWell>(find
                    .descendant(
                        of: existingCard, matching: find.byType(InkWell))
                    .first)
                .onTap,
            isNull);
        final modernChip = find.widgetWithText(ChoiceChip, 'Modern PhilGEPS');
        await tester.ensureVisible(modernChip);
        await tester.tap(modernChip);
        await tester.pumpAndSettle();
        expect((state.filteredPosts as List).map((p) => p.id), ['-130491']);
        final oldChip = find.widgetWithText(ChoiceChip, 'Existing PhilGEPS');
        await tester.tap(oldChip);
        await tester.pumpAndSettle();
        expect((state.filteredPosts as List).map((p) => p.id), ['130491']);
        await tester.pumpWidget(const SizedBox.shrink());
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
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }, client);
  });
}
