import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

String pageText(PdfDocument doc, int index) => PdfTextExtractor(doc)
    .extractText(startPageIndex: index, endPageIndex: index)
    .replaceAll('\u0000', '')
    .replaceAll(RegExp(r'\s+'), '')
    .toUpperCase();

void verifyOrder(PdfDocument doc) {
  final text = [for (var i = 0; i < doc.pages.count; i++) pageText(doc, i)];
  expect(text[2], contains('CLASS'));
  expect(text[3], contains('LEGALDOCUMENTS'));
  expect(text[4], contains('CERTIFICATEOFPHILGEPSREGISTRATION'));
  int find(String title) => text.indexWhere((t) => t.contains(title), 4);
  final order = [
    find('CERTIFICATEOFPHILGEPSREGISTRATION'),
    find('TECHNICALDOCUMENTS'),
    find('STATEMENTOFALLITSONGOING'),
    find('BIDSECURINGDECLARATION'),
    find('TECHNICALSPECIFICATIONS'),
    find('SCHEDULEOFREQUIREMENTS'),
    find('LISTOFMANPOWER'),
    find('SALESSERVICECERTIFICATE'),
    find('CERTIFICATEOFPRODUCTWARRANTY'),
    find('OMNIBUSSWORNSTATEMENT'),
    find('FINANCIALDOCUMENTS'),
    find('NETFINANCIALCONTRACTINGCAPACITY(NFCC)'),
    find('BIDFORM'),
    find('PRICE SCHEDULE FOR GOODS'.replaceAll(' ', '')),
    find('SUMMARYOFBIDPRICES'),
  ];
  expect(order, everyElement(greaterThanOrEqualTo(0)));
  expect(order, orderedEquals([...order]..sort()));
  expect(order.toSet().length, order.length);
  expect(order.last,
      lessThan(doc.pages.count)); // Summary may have continuation pages.
  final ongoing = doc.pages[find('STATEMENTOFALLITSONGOING')].size;
  expect(ongoing.width, greaterThan(ongoing.height));
  final price = doc.pages[find('PRICESCHEDULEFORGOODS')].size;
  expect(price.width, greaterThan(price.height));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const values = {
    'bidderName': 'MIKATA PRIME CORPORATION',
    'projectTitle': 'Supply and Installation of Solar Street Lights',
    'submittedBy': 'MARLJONE BLAIRE B. TINGTING',
    'date': 'September 18, 2026',
    'technicalSpecifications': '[]',
    'priceSchedule': '[]',
    'bidSecuringDeclarationTemplate': 'initao_lgu',
    'omnibusTemplateType': 'initao_lgu',
  };
  test('INITAO groups every completed page without changing text or dimensions',
      () async {
    final source = PdfDocument(
        inputBytes: await PdfService.generateBidDocs(
            values: {...values, 'slccTemplateType': 'streetlight'}));
    final result = PdfDocument(
        inputBytes: await PdfService.generateBidDocs(values: {
      ...values,
      'slccTemplateType': 'streetlight',
      'documentTemplateMode': 'initao'
    }));
    addTearDown(source.dispose);
    addTearDown(result.dispose);
    verifyOrder(result);
    expect(result.pages.count, source.pages.count + 5);
    String signature(PdfDocument d, int i) =>
        '${d.pages[i].size}|${pageText(d, i)}';
    final remaining = [
      for (var i = 0; i < result.pages.count; i++) signature(result, i)
    ];
    for (var i = 0; i < source.pages.count; i++) {
      if (pageText(source, i)
          .contains('CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS')) continue;
      expect(remaining.remove(signature(source, i)), isTrue,
          reason: 'Source page ${i + 1} was lost or changed');
    }
    expect(
        remaining.length, 6); // Only the six INITAO template pages are added.
  }, timeout: const Timeout(Duration(minutes: 8)));
  test(
      'section order remains valid without SLCC and with multiple technical sheets',
      () async {
    final doc = PdfDocument(
        inputBytes: await PdfService.generateBidDocs(values: {
      ...values,
      'documentTemplateMode': 'initao',
      'slccTemplateType': 'none',
      'technicalSpecifications': jsonEncode(List.generate(
          18,
          (i) => {
                'specification': 'Equipment ${i + 1}',
                'quantity': '1',
                'unit': 'set',
                'parameter': 'Comply'
              })),
    }));
    addTearDown(doc.dispose);
    verifyOrder(doc);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
