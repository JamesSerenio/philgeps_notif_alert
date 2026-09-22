@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:philgeps_notif_alert/pdf_editor/screens/pdf_editor_screen.dart';

void main() {
  final writes = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://pricing-test.invalid',
        publishableKey: 'test',
        authOptions: FlutterAuthClientOptions(localStorage: EmptyLocalStorage(), autoRefreshToken: false, detectSessionInUri: false),
        httpClient: MockClient((request) async {
          Object? data;
          if (request.method == 'POST') {
            if (request.url.path.endsWith('bid_technical_specifications')) {
              writes.add(jsonDecode(request.body) as Map<String, dynamic>);
            }
            return http.Response('', 201, request: request);
          }
          if (request.url.path.endsWith('bid_technical_specifications')) {
            data = {
              'specifications': [
                {
                  'specification': 'Solar Street Lights',
                  'quantity': '12',
                  'unit': 'sets'
                },
                {
                  'specification': 'Portland Cement',
                  'quantity': '74',
                  'unit': 'bags'
                },
                {
                  'specification': 'Boom Truck',
                  'quantity': '1 unit x 4 days',
                  'unit': 'unit'
                },
              ]
            };
          } else if (request.url.path.endsWith('bid_price_schedules')) {
            data = {
              'total_prices_per_unit': [
                for (final rate in ['24,780', '300', '6,554'])
                  {'totalPricePerUnit': rate, 'deduction': ''}
              ]
            };
          } else if (request.url.path
              .endsWith('technical_specification_units')) {
            data = <Object>[];
          }
          return http.Response(jsonEncode(data), 200, request: request,
              headers: {'content-type': 'application/json'});
        }));
  });
  setUpAll(() async {
    final row = await Supabase.instance.client.from('bid_technical_specifications').select('specifications').maybeSingle();
    expect(row, isNotNull);
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets('saved prices and edits update immediately without generation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
        home: PdfEditorScreen(
      province: 'Bukidnon',
      municipality: 'Test',
      projectTitle: 'Pricing test',
      referenceNumber: 'pricing-test',
      procuringEntity: 'Test entity',
      date: 'September 18, 2026',
      bidderName: 'Test bidder',
          deliveryPeriod: '30 days',
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PRICE SCHEDULE FOR GOODS'));
    await tester.pumpAndSettle();
    expect(find.text('\u20b1 297,360.00'), findsOneWidget);
    expect(find.text('\u20b1 22,200.00'), findsOneWidget);
    expect(find.text('\u20b1 26,216.00'), findsOneWidget);
    expect(find.text('Grand Total: \u20b1 345,776.00'), findsOneWidget);
    final deductions = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Deduction');
    await tester.enterText(deductions.first, '780');
    await tester.pump();
    expect(find.text('\u20b1 288,000.00'), findsOneWidget);
    expect(find.text('Grand Total: \u20b1 336,416.00'), findsOneWidget);

    await tester.tap(find.text('TECHNICAL SPECIFICATIONS'));
    await tester.pumpAndSettle();
    final qty = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '1 unit x 4 days');
    await tester.enterText(qty, '1 unit x 5 days');
    await tester.pump();
    expect(find.text('\u20b1 32,770.00'), findsOneWidget);
    final changedQty = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '1 unit x 5 days');
    await tester.enterText(changedQty, '2 units x 4 days');
    await tester.pump();
    expect(find.text('\u20b1 52,432.00'), findsOneWidget);
    expect(find.text('Grand Total: \u20b1 362,632.00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final equipment = (writes.last['specifications'] as List).last as Map;
    expect(equipment['quantityValue'], 2);
    expect(equipment['numberOfDays'], 4);
    expect(equipment['pricingType'], 'equipmentDaily');
    expect(find.text('Generating Bid Document'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
