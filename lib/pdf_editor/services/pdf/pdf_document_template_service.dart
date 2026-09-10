part of '../pdf_service.dart';

Future<void> _insertInitaoDocumentPages(PdfDocument document) async {
  final data = await rootBundle.load(
    'assets/pdf/New_tab_and_pages_Initao_LGU_template.pdf',
  );
  final template = PdfDocument(inputBytes: data.buffer.asUint8List());
  try {
    if (template.pages.count != 6) {
      throw StateError('The INITAO document template must contain six pages.');
    }
    // Apply only after all legacy page-index mappings and section moves finish.
    const sourceOrder = [4, 5, 1, 2, 3, 0];
    for (var index = 0; index < sourceOrder.length; index++) {
      final source = template.pages[sourceOrder[index]];
      final target =
          document.pages.insert(index, source.size, PdfMargins()..all = 0);
      target.graphics
          .drawPdfTemplate(source.createTemplate(), Offset.zero, source.size);
    }
  } finally {
    template.dispose();
  }
}
