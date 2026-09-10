import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

List<String> pageWords(PdfDocument document, int page) => [
      for (final line in PdfTextExtractor(document)
          .extractTextLines(startPageIndex: page, endPageIndex: page))
        for (final word in line.wordCollection)
          '${word.text}|${word.bounds}|${word.fontName}|${word.fontSize}',
    ];
void comparePages(PdfDocument expected, PdfDocument actual, {int offset = 0}) {
  expect(actual.pages.count, expected.pages.count + offset);
  for (var page = 0; page < expected.pages.count; page++) {
    expect(actual.pages[page + offset].size, expected.pages[page].size);
    expect(pageWords(actual, page + offset), pageWords(expected, page),
        reason: 'Existing page ${page + 1}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const values = {
    'province': 'Misamis Oriental',
    'municipality': 'Initao',
    'projectTitle': 'Supply and Installation of Solar Street Lights',
    'procuringEntity': 'MUNICIPALITY OF INITAO, MISAMIS ORIENTAL',
    'referenceNumber': '13213399',
    'date': 'September 18, 2026',
    'bidderName': 'MIKATA PRIME CORPORATION',
    'submittedBy': 'MARLJONE BLAIRE B. TINGTING',
    'technicalSpecifications': '[]',
    'priceSchedule': '[]',
  };
  Future<PdfDocument> generate(Map<String, String> options) async {
    final result = PdfDocument(
        inputBytes:
            await PdfService.generateBidDocs(values: {...values, ...options}));
    addTearDown(result.dispose);
    return result;
  }

  test(
      'OLD global mode rejects stale INITAO choices and preserves legacy pages',
      () async {
    final baseline = await generate({
      'omnibusTemplateType': 'old',
      'bidSecuringDeclarationTemplate': 'old'
    });
    final old = await generate({
      'documentTemplateMode': 'old',
      'omnibusTemplateType': 'initao_lgu',
      'bidSecuringDeclarationTemplate': 'initao_lgu'
    });
    comparePages(baseline, old);
  }, timeout: const Timeout(Duration(minutes: 5)));
  test(
      'INITAO global mode forces both variants and prefixes six pages in 5,6,2,3,4,1 order',
      () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    const asset = 'assets/pdf/New_tab_and_pages_Initao_LGU_template.pdf';
    expect(manifest.listAssets(), contains(asset));
    final template = PdfDocument(inputBytes: File(asset).readAsBytesSync());
    addTearDown(template.dispose);
    expect(template.pages.count, 6);
    final baseline = await generate({
      'omnibusTemplateType': 'initao_lgu',
      'bidSecuringDeclarationTemplate': 'initao_lgu'
    });
    final initao = await generate({
      'documentTemplateMode': 'initao',
      'omnibusTemplateType': 'old',
      'bidSecuringDeclarationTemplate': 'old'
    });
    comparePages(baseline, initao, offset: 6);
    const order = [4, 5, 1, 2, 3, 0];
    for (var page = 0; page < order.length; page++) {
      expect(initao.pages[page].size, template.pages[order[page]].size);
      expect(pageWords(initao, page), pageWords(template, order[page]),
          reason: 'Template page order');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
