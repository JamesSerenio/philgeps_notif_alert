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
  // source page is removed from the destination, so this is a moveÃ¢â‚¬â€not a
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

/// Removes only the unused tail of a renderer-owned template allocation.
///
/// The caller supplies the section start captured immediately before that
/// renderer runs, the number of template pages exclusively allocated to it,
/// and the exact number of pages the renderer consumed.  This deliberately
/// does not inspect text or visual emptiness: scanned supporting documents
/// may have no extractable text and must never be removed by this helper.
int _removeUnusedSectionTemplatePages(
  PdfDocument document, {
  required String sectionName,
  required int startPageIndex,
  required int allocatedPages,
  required int usedPages,
}) {
  final safeUsedPages = usedPages.clamp(1, allocatedPages).toInt();
  final firstUnusedIndex = startPageIndex + safeUsedPages;
  final endExclusive = startPageIndex + allocatedPages;
  final pageCountBefore = document.pages.count;
  final removedIndexes = <int>[];

  if (startPageIndex < 0 ||
      allocatedPages <= 0 ||
      firstUnusedIndex >= endExclusive) {
    print(
      'PDF CLEANUP $sectionName: start=$startPageIndex '
      'allocated=$allocatedPages used=$usedPages removed=[] '
      'before=$pageCountBefore after=${document.pages.count}',
    );
    return 0;
  }

  // Removing downward keeps the unremoved section pages and every later
  // anchor stable until this section cleanup is complete.
  for (var pageIndex = endExclusive - 1;
      pageIndex >= firstUnusedIndex;
      pageIndex--) {
    if (pageIndex < document.pages.count) {
      document.pages.removeAt(pageIndex);
      removedIndexes.add(pageIndex);
    }
  }

  print(
    'PDF CLEANUP $sectionName: start=$startPageIndex '
    'allocated=$allocatedPages used=$usedPages '
    'removed=${removedIndexes.reversed.toList()} '
    'before=$pageCountBefore after=${document.pages.count}',
  );
  return removedIndexes.length;
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
