import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/models/item_pricing.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('currency inputs, optional deduction and 50/20/30 composition', () {
    for (final input in [
      '24780',
      '24,780',
      '24,780.00',
      '\u20b124,780.00',
      '\u20b1 24,780.00'
    ]) {
      final price = ItemPricing.fromMaps(
          {'quantityValue': 12}, {'totalPricePerUnit': input, 'deduction': ''});
      expect(price.totalDeliveredPrice, 297360);
      expect(price.unitPriceComponent, 12390);
      expect(price.transportInsuranceComponent, 4956);
      expect(price.taxComponent, 7434);
    }
    final discounted = ItemPricing.fromMaps({'quantityValue': 12},
        {'totalPricePerUnit': '24,780', 'deduction': '780'});
    expect(discounted.adjustedUnitPrice, 24000);
    expect(discounted.totalDeliveredPrice, 288000);
    expect(discounted.unitPriceComponent, 12000);
    expect(discounted.transportInsuranceComponent, 4800);
    expect(discounted.taxComponent, 7200);
    expect(
        ItemPricing(quantity: const PricingQuantity(74), unitPrice: 300)
            .totalDeliveredPrice,
        22200);
    expect(
        ItemPricing(quantity: const PricingQuantity(3), unitPrice: 1.25)
            .totalDeliveredPrice,
        3.75);
  });

  test('units and days both affect equipment totals and survive persistence',
      () {
    for (final row in [
      (1.0, 4.0, 26216.0),
      (1.0, 5.0, 32770.0),
      (2.0, 4.0, 52432.0)
    ]) {
      final quantity = PricingQuantity(row.$1,
          numberOfDays: row.$2, type: PricingType.equipmentDaily);
      final restored =
          PricingQuantity.fromMap(jsonDecode(jsonEncode(quantity.toMap())));
      expect(
          ItemPricing(quantity: restored, unitPrice: 6554).totalDeliveredPrice,
          row.$3);
    }
    final legacy = PricingQuantity.fromInput('1 unit \u00d7 4 days');
    expect(legacy.type, PricingType.equipmentDaily);
    expect(legacy.effectiveQuantity, 4);
    expect(PricingQuantity.fromInput('2 units x 4 days unit').effectiveQuantity,
        8);
    expect(PricingQuantity.fromInput('74 bags').effectiveQuantity, 74);
    // Structured numeric fields, not the display string, control calculations.
    final structured = PricingQuantity.fromMap({
      'quantity': 'wrong display',
      'quantityValue': 2,
      'numberOfDays': 4,
      'pricingType': 'equipmentDaily'
    });
    expect(structured.effectiveQuantity, 8);
  });

  test(
      'generated price schedule matches shared totals including equipment days',
      () async {
    final specifications = [
      {
        'specification':
            'Installation of 12 units of Solar Street Lights\u2029Solar Panel: 12V 200W\u2029Battery: LiFePO4\u2029LED Lamp: 120W True Rated',
        'quantity': '12',
        'unit': 'sets',
        ...const PricingQuantity(12).toMap()
      },
      {
        'specification': 'Portland Cement',
        'quantity': '74',
        'unit': 'bags',
        ...const PricingQuantity(74).toMap()
      },
      {
        'specification': 'Boom Truck',
        'quantity': '1 unit x 4 days',
        'unit': 'unit',
        ...const PricingQuantity(1,
                numberOfDays: 4, type: PricingType.equipmentDaily)
            .toMap()
      },
    ];
    final prices = [
      for (final price in [24780, 300, 6554])
        {
          'totalPricePerUnit': price.toString(),
          'deduction': '',
          'isManualTotalOverride': false,
          'manualTotal': ''
        }
    ];
    final bytes = await PdfService.generateBidDocs(values: {
      'projectTitle': 'Pricing regression',
      'date': 'September 18, 2026',
      'technicalSpecifications': jsonEncode(specifications),
      'priceSchedule': jsonEncode(prices),
      'includeScheduleTotal': 'true',
    });
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      final schedulePages = <String>[];
      for (var i = 0; i < document.pages.count; i++) {
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        if (text.toUpperCase().contains('PRICE SCHEDULE FOR GOODS'))
          schedulePages.add(text);
      }
      expect(schedulePages, isNotEmpty);
      final text = schedulePages.join('\n');
      final normalizedText = text.replaceAll(RegExp(r'\s+'), ' ');
      for (final amount in [
        '297,360.00',
        'Solar Panel: 12V 200W',
        'Battery: LiFePO4',
        'LED Lamp: 120W True Rated',
        '22,200.00',
        '26,216.00',
        '345,776.00'
      ]) {
        expect(normalizedText, contains(amount));
      }
      expect(text.replaceAll(RegExp(r'\s+'), ' '), contains('1 x 4 days'));
    } finally {
      document.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
