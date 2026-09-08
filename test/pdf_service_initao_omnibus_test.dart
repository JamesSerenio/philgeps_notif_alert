import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('INITAO adds 1-11 in place and preserves OLD content and page count',
      () async {
    const values = {
      'submittedBy': 'MARLJONE BLAIRE B. TINGTING',
      'bidderName': 'MIKATA PRIME CORPORATION',
      'projectTitle': 'Supply and Installation of Solar Street Lights',
      'procuringEntity': 'MUNICIPALITY OF INITAO, MISAMIS ORIENTAL',
      'date': 'September 8, 2026',
      'technicalSpecifications': '[]',
      'priceSchedule': '[]',
    };
    final old = PdfDocument(
        inputBytes: await PdfService.generateBidDocs(
            values: {...values, 'omnibusTemplateType': 'old'}));
    final initao = PdfDocument(
        inputBytes: await PdfService.generateBidDocs(
            values: {...values, 'omnibusTemplateType': 'initao_lgu'}));
    addTearDown(old.dispose);
    addTearDown(initao.dispose);
    expect(initao.pages.count, old.pages.count);
    final oldExtractor = PdfTextExtractor(old);
    final newExtractor = PdfTextExtractor(initao);
    var omnibus = -1;
    for (var page = old.pages.count ~/ 2; page < old.pages.count; page++) {
      final text =
          oldExtractor.extractText(startPageIndex: page, endPageIndex: page);
      if (text
          .replaceAll(RegExp(r'\s+'), '')
          .toUpperCase()
          .contains('OMNIBUSSWORNSTATEMENT')) {
        omnibus = page;
        break;
      }
    }
    expect(omnibus, greaterThanOrEqualTo(0));
    final addedLabels = <int>[];
    for (var page = 0; page < old.pages.count; page++) {
      List<String> words(PdfTextExtractor extractor) => [
            for (final line in extractor.extractTextLines(
                startPageIndex: page, endPageIndex: page))
              for (final word in line.wordCollection)
                '${word.text}|${word.bounds}',
          ];
      final before = words(oldExtractor);
      final after = words(newExtractor);
      // Every existing word remains at exactly the same position.
      for (final word in before) {
        expect(after.remove(word), isTrue, reason: 'Page $page: $word');
      }
      if (page == omnibus || page == omnibus + 1) {
        for (final word in after) {
          final text = word.split('|').first;
          expect(text, matches(RegExp(r'^\d+\.$')));
          addedLabels.add(int.parse(text.substring(0, text.length - 1)));
        }
      } else {
        expect(after, isEmpty, reason: 'Unrelated page $page changed');
      }
    }
    addedLabels.sort();
    expect(addedLabels, List.generate(11, (index) => index + 1));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
