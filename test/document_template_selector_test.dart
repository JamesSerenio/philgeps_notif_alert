@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:philgeps_notif_alert/pdf_editor/screens/pdf_editor_screen.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://mode-test.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async => http.Response(
            request.url.path.endsWith('philgeps_posts')
                ? '[{"delivery_period":"30 Days"}]'
                : '[]',
            200,
            headers: {'content-type': 'application/json'},
          )),
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          localStorage: EmptyLocalStorage(),
          detectSessionInUri: false),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets(
      'global mode switches immediately, restores, and never generates on selection',
      (tester) async {
    await http.runWithClient(() async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget editor() => const MaterialApp(
              home: PdfEditorScreen(
            province: 'Misamis Oriental',
            municipality: 'Initao',
            projectTitle: 'Test bid',
            referenceNumber: 'mode-test',
            date: 'September 18, 2026',
            bidderName: 'Test bidder',
            procuringEntity: 'Initao',
            deliveryPeriod: '30 Days',
          ));
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();
      Finder global() => find.byWidgetPredicate((widget) =>
          widget is SegmentedButton<String> &&
          widget.segments.any((s) => s.value == 'initao'));
      SegmentedButton<String> globalWidget() =>
          tester.widget<SegmentedButton<String>>(global());
      expect(globalWidget().selected, {'old'});
      expect(find.text('INITAO LGU'), findsNothing);
      await tester.tap(find.text('BID SECURING DECLARATION'));
      await tester.pumpAndSettle();
      expect(find.text('WITHOUT TABLE'), findsOneWidget);
      await tester.tap(find.text('WITHOUT TABLE'));
      await tester.pumpAndSettle();
      // Rapid changes remain enabled while background writes are queued.
      for (final mode in ['initao', 'old', 'initao']) {
        expect(globalWidget().onSelectionChanged, isNotNull);
        globalWidget().onSelectionChanged!({mode});
        await tester.pump();
        expect(globalWidget().selected, {mode});
        expect(find.text('Generating Bid Document'), findsNothing);
        expect(find.text('Generating...'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(find.text('INITAO LGU'), findsNWidgets(2));
      expect(find.text('WITHOUT TABLE'), findsNothing);
      expect(
          (await SharedPreferences.getInstance())
              .getString('bid_document_template_mode-test'),
          'initao');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(editor());
      await tester.pumpAndSettle();
      expect(globalWidget().selected, {'initao'});
      expect(find.text('Generating Bid Document'), findsNothing);
      globalWidget().onSelectionChanged!({'old'});
      await tester.pumpAndSettle();
      await tester.tap(find.text('BID SECURING DECLARATION'));
      await tester.pumpAndSettle();
      final declaration = tester.widget<SegmentedButton<String>>(
          find.byWidgetPredicate((w) =>
              w is SegmentedButton<String> &&
              w.segments.any((s) => s.value == 'without_table')));
      expect(declaration.selected, {'without_table'});
      expect(find.text('INITAO LGU'), findsNothing);
      // Complete unrelated delivery-refresh timeout cleanup in the fake clock.
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
        () => MockClient(
            (_) async => http.Response('{"deliveryPeriod":"30 Days"}', 200)));
  });
}
