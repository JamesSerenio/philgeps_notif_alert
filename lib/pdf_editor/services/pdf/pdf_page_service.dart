part of '../pdf_service.dart';

Future<void> _moveBusinessPermitBeforeTaxClearance(
  PdfDocument document,
) async {
  // The Business Permit is the original PDF page 3. Reorder only after all
  // fixed-index drawing/replacement work is complete, so those mappings keep
  // referring to their original template pages during generation.
  const businessPermitPageIndex = 2;
  const taxClearancePageIndex = 10;
  if (document.pages.count <= taxClearancePageIndex) return;

  // Keep the source document alive until its template has been drawn. The
  // source page is removed from the destination, so this is a moveâ€”not a
  // duplicate Business Permit page.
  final snapshotBytes = await document.save();
  final snapshotDocument = PdfDocument(inputBytes: snapshotBytes);
  final sourcePage = snapshotDocument.pages[businessPermitPageIndex];
  final sourceSize = sourcePage.size;
  final sourceTemplate = sourcePage.createTemplate();

  document.pages.removeAt(businessPermitPageIndex);
  // Removing page 3 shifts the original page 11 to index 9. Insert at that
  // index so Business Permit becomes page 10 and Tax Clearance remains 11.
  const insertionIndex = taxClearancePageIndex - 1;
  final targetPage = document.pages.insert(
    insertionIndex,
    sourceSize,
    PdfMargins()..all = 0,
  );
  targetPage.graphics.drawPdfTemplate(
    sourceTemplate,
    Offset.zero,
    sourceSize,
  );
  snapshotDocument.dispose();
}

void _replacePagesWithBlankSize(
  PdfDocument document,
  int startPageIndex,
  int pageCount,
  Size pageSize,
) {
  final removableCount =
      pageCount.clamp(0, document.pages.count - startPageIndex).toInt();
  for (var index = 0; index < removableCount; index++) {
    document.pages.removeAt(startPageIndex);
  }
  for (var index = 0; index < removableCount; index++) {
    document.pages.insert(
      startPageIndex + index,
      pageSize,
      PdfMargins()..all = 0,
    );
  }
}

int _findPageContaining(
  PdfDocument document,
  List<String> phrases,
) {
  final lines = PdfTextExtractor(document).extractTextLines(
    startPageIndex: 0,
    endPageIndex: document.pages.count - 1,
  );
  for (final line in lines) {
    final text = line.text.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    if (phrases.any((phrase) => text.contains(phrase))) {
      return line.pageIndex;
    }
  }
  return -1;
}
