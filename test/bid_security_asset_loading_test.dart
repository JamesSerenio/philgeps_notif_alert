import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all declaration assets load from the registered bundle', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final path in [
      'assets/pdf/bidocs_template.pdf',
      'assets/pdf/BID SECURING DECLARATION_impasugong_template.pdf',
      'assets/pdf/BID SECURING DECLARATION_initao_template.pdf',
    ]) {
      expect(manifest.listAssets(), contains(path));
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0));
      expect(String.fromCharCodes(data.buffer.asUint8List().take(5)), '%PDF-');
    }
  });
  for (final option in ['old', 'without_table', 'initao_lgu']) {
    test('generates declaration option ' + option, () async {
      final bidDate = {
        'old': 'September 8, 2026',
        'without_table': 'September 1, 2026',
        'initao_lgu': 'December 31, 2026',
      }[option]!;
      final bytes = await PdfService.generateBidDocs(values: {
        'bidSecuringDeclarationTemplate': option,
        'submittedBy': 'MARLJONE BLAIRE B. TINGTING',
        'bidderName': 'MIKATA PRIME CORPORATION',
        'municipality': 'Initao',
        'procuringEntity': 'MUNICIPALITY OF INITAO, MISAMIS ORIENTAL',
        'referenceNumber': '13213399',
        'projectTitle': 'Supply and Installation of Solar Street Lights',
        'date': bidDate,
        'technicalSpecifications': '[]',
        'priceSchedule': '[]',
      });
      expect(bytes, isNotEmpty);
      final document = PdfDocument(inputBytes: bytes);
      final lines = PdfTextExtractor(document).extractTextLines();
      final nfccPage = lines
          .firstWhere((line) =>
              line.text.contains('NET FINANCIAL CONTRACTING CAPACITY'))
          .pageIndex;
      final nfccText = lines
          .where((line) => line.pageIndex == nfccPage)
          .map((line) => line.text)
          .join('\n');
      expect(nfccText, contains(bidDate));
      expect(nfccText, isNot(contains('September 9, 2026')));
      final page = lines
          .firstWhere((line) => line.text.contains('BID SECURING DECLARATION'))
          .pageIndex;
      final text = lines
          .where((line) => line.pageIndex == page)
          .map((line) => line.text)
          .join('\n');
      if (option == 'without_table') {
        expect(text, contains('Upon contract award and the LCCRB'));
      } else if (option == 'initao_lgu') {
        expect(text, isNot(contains('LCCRB')));
        expect(text, contains('c) I am/we are declared the bidder'));
        expect(text, isNot(contains('d) I am/we are declared the bidder')));
      }
      document.dispose();
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
