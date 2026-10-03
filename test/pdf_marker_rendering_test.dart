import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders specification markers as their selected Unicode glyphs',
      () async {
    const specification = '''TEST NONE
• TEST BULLET
○ TEST CIRCLE
■ TEST SQUARE
➢ TEST ARROW
✓ TEST CHECK''';
    final values = <String, String>{
      'province': 'Misamis Oriental',
      'municipality': 'Initao',
      'referenceNumber': 'MARKER-001',
      'procuringEntity': 'MUNICIPALITY OF INITAO, MISAMIS ORIENTAL',
      'projectTitle': 'SOLAR STREET LIGHT MARKER TEST',
      'date': 'October 3, 2026',
      'bidderName': 'MARKER TEST BIDDER',
      'submittedBy': 'MARKER TEST REPRESENTATIVE',
      'technicalSpecifications': jsonEncode(<Map<String, String>>[
        <String, String>{
          'specification': specification,
          'quantity': '1',
          'unit': 'set',
          'parameter': '',
        },
      ]),
      'priceSchedule': jsonEncode(<Map<String, String>>[
        <String, String>{
          'specification': specification,
          'quantity': '1',
          'unit': 'set',
          'totalPricePerUnit': '1000',
          'deduction': '',
        },
      ]),
      'deliveredWeeksMonths': '30 Day/s',
      'bidSecuringDeclarationWithTable': 'true',
    };

    final bytes = await PdfService.generateBidDocs(values: values);
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    for (final markerLine in const <String>[
      'TEST NONE',
      '• TEST BULLET',
      '○ TEST CIRCLE',
      '■ TEST SQUARE',
      '➢ TEST ARROW',
      '✓ TEST CHECK',
    ]) {
      expect(text, contains(markerLine));
    }
    expect(text, isNot(contains('v TEST CHECK')));
  });
}
