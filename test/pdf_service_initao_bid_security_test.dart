import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

List<String> _words(PdfDocument document, int page) => [
      for (final line in PdfTextExtractor(document)
          .extractTextLines(startPageIndex: page, endPageIndex: page))
        for (final word in line.wordCollection)
          '${word.text}|${word.bounds}|${word.fontName}|${word.fontSize}',
    ];

void _expectOnlyItemThreeCorrection(
    PdfDocument original, PdfDocument corrected, int page) {
  expect(corrected.pages.count, original.pages.count);
  final extractor = PdfTextExtractor(original);
  final lines =
      extractor.extractTextLines(startPageIndex: page, endPageIndex: page);
  final removed = lines.singleWhere(
      (line) => line.text.contains('Upon contract award and the LCCRB'));
  final oldFinal = lines.firstWhere(
      (line) => line.text.startsWith('d) I am/we are declared the bidder'));
  final removedWords = {
    for (final word in removed.wordCollection)
      '${word.text}|${word.bounds}|${word.fontName}|${word.fontSize}',
  };
  final oldLabel = oldFinal.wordCollection.first;
  removedWords.add(
      '${oldLabel.text}|${oldLabel.bounds}|${oldLabel.fontName}|${oldLabel.fontSize}');
  for (var index = 0; index < original.pages.count; index++) {
    expect(corrected.pages[index].size, original.pages[index].size);
    final before = _words(original, index);
    final after = _words(corrected, index);
    if (index != page) {
      expect(after, before, reason: 'Unrelated page $index');
      continue;
    }
    before.removeWhere(removedWords.contains);
    final newLabel = PdfTextExtractor(corrected)
        .extractTextLines(startPageIndex: page, endPageIndex: page)
        .expand((line) => line.wordCollection)
        .singleWhere((word) =>
            word.text == 'c)' &&
            (word.bounds.top - oldLabel.bounds.top).abs() < .01);
    expect(newLabel.bounds.topLeft, oldLabel.bounds.topLeft);
    expect(newLabel.fontName, oldLabel.fontName);
    expect(newLabel.fontSize, oldLabel.fontSize);
    after.remove(
        '${newLabel.text}|${newLabel.bounds}|${newLabel.fontName}|${newLabel.fontSize}');
    expect(after, before, reason: 'Only the old c) and d) label may change');
  }
  final correctedText = PdfTextExtractor(corrected)
      .extractTextLines(startPageIndex: page, endPageIndex: page)
      .map((line) => line.text)
      .join('\n');
  expect(correctedText, isNot(contains('LCCRB')));
  final itemThree =
      correctedText.substring(correctedText.indexOf('3. I/We understand'));
  expect(
      RegExp(r'\b([a-d])\)')
          .allMatches(itemThree)
          .map((match) => match.group(1))
          .toList(),
      ['a', 'b', 'c']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('INITAO template changes only Item 3 c) and d)', () {
    final original = PdfDocument(
        inputBytes:
            File('assets/pdf/BID SECURING DECLARATION_impasugong_template.pdf')
                .readAsBytesSync());
    final corrected = PdfDocument(
        inputBytes:
            File('assets/pdf/BID SECURING DECLARATION_initao_template.pdf')
                .readAsBytesSync());
    addTearDown(original.dispose);
    addTearDown(corrected.dispose);
    _expectOnlyItemThreeCorrection(original, corrected, 0);
  });

  test('generation selects INITAO in place and preserves all other pages',
      () async {
    const values = {
      'province': 'Misamis Oriental',
      'municipality': 'Initao',
      'referenceNumber': '13213399',
      'procuringEntity': 'MUNICIPALITY OF INITAO, MISAMIS ORIENTAL',
      'bidderName': 'MIKATA PRIME CORPORATION',
      'submittedBy': 'MARLJONE BLAIRE B. TINGTING',
      'submittedByFormalName': 'Marljone Blaire B. Tingting',
      'date': 'September 8, 2026',
      'projectTitle': 'Supply and Installation of Solar Street Lights',
      'technicalSpecifications': '[]',
      'priceSchedule': '[]',
      // The explicit variant takes precedence over this legacy option.
      'bidSecuringDeclarationWithTable': 'true',
    };
    final original = PdfDocument(
        inputBytes: await PdfService.generateBidDocs(values: {
      ...values,
      'bidSecuringDeclarationTemplate': 'without_table'
    }));
    final corrected = PdfDocument(
        inputBytes: await PdfService.generateBidDocs(values: {
      ...values,
      'bidSecuringDeclarationTemplate': 'initao_lgu'
    }));
    addTearDown(original.dispose);
    addTearDown(corrected.dispose);
    final page = PdfTextExtractor(original)
        .extractTextLines()
        .firstWhere((line) => line.text.contains('BID SECURING DECLARATION'))
        .pageIndex;
    _expectOnlyItemThreeCorrection(original, corrected, page);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
