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
  // source page is removed from the destination, so this is a move—not a
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

Future<void> _movePriceAndSummaryToDocumentEnd(
  PdfDocument document, {
  required int priceStart,
  required int summaryStart,
  required int priceSchedulePageCount,
  required int summaryPageCount,
}) async {
  if (priceStart < 0 ||
      summaryStart <= priceStart ||
      summaryStart >= document.pages.count) {
    return;
  }

  final safePriceCount = priceSchedulePageCount
      .clamp(0, document.pages.count - priceStart)
      .toInt();
  final safeSummaryCount =
      summaryPageCount.clamp(0, document.pages.count - summaryStart).toInt();
  if (safePriceCount == 0 || safeSummaryCount == 0) return;

  // Snapshot both completed sections before removing either range. Imported
  // templates remain valid because this source document stays alive until
  // every moved page has been appended to the destination document.
  final snapshotBytes = await document.save();
  final snapshotDocument = PdfDocument(inputBytes: snapshotBytes);
  final pricePages = <({PdfTemplate template, Size size})>[
    for (var index = 0; index < safePriceCount; index++)
      (
        template: snapshotDocument.pages[priceStart + index].createTemplate(),
        size: snapshotDocument.pages[priceStart + index].size,
      ),
  ];
  final summaryPages = <({PdfTemplate template, Size size})>[
    for (var index = 0; index < safeSummaryCount; index++)
      (
        template: snapshotDocument.pages[summaryStart + index].createTemplate(),
        size: snapshotDocument.pages[summaryStart + index].size,
      ),
  ];

  // Remove the later range first so the earlier Price Schedule indexes do
  // not shift. Then append Price Schedule followed by Summary, making the
  // Summary of Bid Prices the final section in the PDF.
  for (var index = 0; index < safeSummaryCount; index++) {
    document.pages.removeAt(summaryStart);
  }
  for (var index = 0; index < safePriceCount; index++) {
    document.pages.removeAt(priceStart);
  }

  for (final source in <({PdfTemplate template, Size size})>[
    ...pricePages,
    ...summaryPages,
  ]) {
    final target = document.pages.insert(
      document.pages.count,
      source.size,
      PdfMargins()..all = 0,
    );
    target.graphics.drawPdfTemplate(
      source.template,
      Offset.zero,
      source.size,
    );
  }
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
