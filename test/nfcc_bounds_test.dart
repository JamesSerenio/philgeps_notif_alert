import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('prints NFCC template text bounds', () {
    final bytes = File('assets/pdf/NFCC_Template.pdf').readAsBytesSync();
    final document = PdfDocument(inputBytes: bytes);
    final page = document.pages[0];
    // ignore: avoid_print
    print('PAGE ${page.size.width} x ${page.size.height}');
    for (final line in PdfTextExtractor(document).extractTextLines()) {
      // ignore: avoid_print
      print('${line.bounds} | ${line.fontSize} | ${line.text}');
    }
    document.dispose();
  });
}
