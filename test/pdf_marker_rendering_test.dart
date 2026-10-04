import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('draws an isolated Unicode check glyph with the bundled font', () async {
    final data = await rootBundle.load('assets/fonts/seguisym.ttf');
    final font = PdfTrueTypeFont(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      12,
    );
    expect(font.measureString('\u2713').width, greaterThan(0));

    final document = PdfDocument();
    final page = document.pages.add();
    page.graphics.drawString(
      '\u2713',
      font,
      bounds: const Rect.fromLTWH(48, 48, 32, 24),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.none),
    );
    final bytes = await document.save();
    document.dispose();
    await Directory('build/test_logs').create(recursive: true);
    await File('build/test_logs/isolated_check_glyph.pdf').writeAsBytes(bytes);
    expect(bytes, isNotEmpty);
  });

  test('renders specification markers as their selected Unicode glyphs',
      () async {
    const specification = '''TEST NONE
• TEST BULLET
○ TEST CIRCLE
■ TEST SQUARE
➢ TEST ARROW
✓ TEST CHECK
v TEST LEGACY CHECK''';
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

    final fontBytes = await rootBundle.load('assets/fonts/seguisym.ttf');
    expect(fontBytes.lengthInBytes, greaterThan(0));

    final bytes = await PdfService.generateBidDocs(values: values);
    await Directory('build/test_logs').create(recursive: true);
    await File('build/test_logs/pdf_marker_rendering.pdf').writeAsBytes(bytes);
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    // Syncfusion's extractor does not map the embedded symbol font glyphs back
    // to Unicode.  Verify the four production table renderers received every
    // line and that no legacy ASCII checkmark substitution survived.
    for (final markerLine in const <String>[
      'TEST NONE',
      'TEST BULLET',
      'TEST CIRCLE',
      'TEST SQUARE',
      'TEST ARROW',
      'TEST CHECK',
      'TEST LEGACY CHECK',
    ]) {
      expect(
          RegExp(markerLine).allMatches(text).length, greaterThanOrEqualTo(4));
    }
    expect(text, isNot(contains('v TEST CHECK')));
  });
}
