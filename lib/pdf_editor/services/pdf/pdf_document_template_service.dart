part of '../pdf_service.dart';

Future<void> _insertInitaoDocumentPages(
  PdfDocument document,
  Map<String, String> values,
) async {
  final data = await rootBundle.load(
    'assets/pdf/New_tab_and_pages_Initao_LGU_template.pdf',
  );
  final template = PdfDocument(inputBytes: data.buffer.asUint8List());
  PdfDocument? snapshot;
  try {
    if (template.pages.count != 6) {
      throw StateError('The INITAO document template must contain six pages.');
    }
    // All autofill and optional section replacements finish before ordering.
    // Work from a live snapshot so removing destination pages cannot invalidate
    // imported templates, including scanned attachments and their overlays.
    snapshot = PdfDocument(inputBytes: await document.save());
    final extractor = PdfTextExtractor(snapshot);
    final text = [
      for (var i = 0; i < snapshot.pages.count; i++)
        extractor
            .extractText(startPageIndex: i, endPageIndex: i)
            .replaceAll('\u0000', '')
            .replaceAll(RegExp(r'\s+'), '')
            .toUpperCase(),
    ];
    int anchor(String title) {
      final index = text.indexWhere((value) =>
          !value.contains('CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS') &&
          value.contains(title));
      if (index < 0) {
        throw StateError('Cannot organize INITAO PDF: missing section $title.');
      }
      return index;
    }

    final ongoing = anchor('STATEMENTOFALLITSONGOING');
    final philgeps = anchor('CERTIFICATEOFPHILGEPSREGISTRATION');
    final nfcc = anchor('NETFINANCIALCONTRACTINGCAPACITY(NFCC)');
    final specifications = anchor('TECHNICALSPECIFICATIONS');
    final security = anchor('BIDSECURINGDECLARATION');
    final schedule = anchor('SCHEDULEOFREQUIREMENTS');
    final omnibus = anchor('OMNIBUSSWORNSTATEMENT');
    final afterSales = anchor('SALESSERVICECERTIFICATE');
    final bidForm = anchor('BIDFORM');

    // AFS consists of scanned pages without reliable text. Its replacement
    // asset supplies its length; NFCC marks the end, even when SLCC is omitted.
    final afsData = await rootBundle.load('assets/pdf/AFS_template.pdf');
    final afsTemplate = PdfDocument(inputBytes: afsData.buffer.asUint8List());
    final afs = nfcc - afsTemplate.pages.count;
    afsTemplate.dispose();
    final boundaries = [
      ongoing,
      philgeps,
      afs,
      nfcc,
      specifications,
      security,
      schedule,
      omnibus,
      afterSales,
      bidForm,
      snapshot.pages.count
    ];
    for (var i = 1; i < boundaries.length; i++) {
      if (boundaries[i] <= boundaries[i - 1]) {
        throw StateError(
            'Cannot organize INITAO PDF: unexpected section boundaries: $boundaries.');
      }
    }
    List<int> range(int start, int end) => [
          for (var i = start; i < end; i++)
            if (!text[i].contains('CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS'))
              i,
        ];
    // Logical groups follow the INITAO checklist. Continuation pages remain
    // attached to their section; no final page numbers are hardcoded.
    final legalDocuments = [...range(philgeps, afs), ...range(0, ongoing)];
    final technicalDocuments = [
      ...range(ongoing, philgeps), // Ongoing contracts, SLCC and acceptance
      ...range(security, schedule),
      ...range(specifications, security),
      ...range(schedule, omnibus), // Delivery schedule and manpower
      ...range(afterSales, bidForm), // After-sales and warranty
      ...range(omnibus, afterSales), // Omnibus, including its jurat
    ];
    final financialDocuments = range(afs, specifications); // AFS then NFCC
    final financialComponentDocuments = range(bidForm, snapshot.pages.count);
    final ordered = [
      ...legalDocuments,
      ...technicalDocuments,
      ...financialDocuments,
      ...financialComponentDocuments
    ];
    final expected = range(0, snapshot.pages.count);
    if (ordered.length != expected.length ||
        ordered.toSet().length != expected.length ||
        !ordered.toSet().containsAll(expected)) {
      throw StateError(
          'Cannot organize INITAO PDF: duplicate or missing pages.');
    }

    _drawInitaoContentsFields(template.pages[0], values);
    final finalPages = <PdfPage>[
      template.pages[4], template.pages[5], // Existing introduction
      template.pages[0], // Checklist immediately before Legal
      template.pages[1],
      for (final i in legalDocuments) snapshot.pages[i],
      template.pages[2],
      for (final i in technicalDocuments) snapshot.pages[i],
      template.pages[3],
      for (final i in financialDocuments) snapshot.pages[i],
      for (final i in financialComponentDocuments) snapshot.pages[i],
    ];
    for (var i = document.pages.count - 1; i >= 0; i--) {
      document.pages.removeAt(i);
    }
    for (final source in finalPages) {
      final target = document.pages
          .insert(document.pages.count, source.size, PdfMargins()..all = 0);
      target.graphics
          .drawPdfTemplate(source.createTemplate(), Offset.zero, source.size);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  } finally {
    snapshot?.dispose();
    template.dispose();
  }
}

void _drawInitaoContentsFields(PdfPage page, Map<String, String> values) {
  final graphics = page.graphics;
  final white = PdfSolidBrush(PdfColor(255, 255, 255));
  final black = PdfSolidBrush(PdfColor(0, 0, 0));
  final regular = PdfStandardFont(PdfFontFamily.timesRoman, 12);
  final bold =
      PdfStandardFont(PdfFontFamily.timesRoman, 12, style: PdfFontStyle.bold);
  // Only cover variable header areas. Labels, colons, Republic heading,
  // table rules, and the entire contents listing remain in the source PDF.
  graphics.drawRectangle(
      brush: white, bounds: const Rect.fromLTWH(150, 51, 295, 29));
  graphics.drawRectangle(
      brush: white, bounds: const Rect.fromLTWH(178, 107, 385, 58));
  final center = PdfStringFormat(alignment: PdfTextAlignment.center);
  graphics.drawString(
      'Province Of ' + (values['province'] ?? '').trim(), regular,
      brush: black,
      bounds: const Rect.fromLTWH(150, 52.6, 295, 14),
      format: center);
  graphics.drawString(
      'Municipality of ' + (values['municipality'] ?? '').trim(), regular,
      brush: black,
      bounds: const Rect.fromLTWH(150, 66.1, 295, 14),
      format: center);
  graphics.drawString((values['projectTitle'] ?? '').trim(), bold,
      brush: black,
      bounds: const Rect.fromLTWH(180.2, 108.9, 379, 27.7),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.word));
  graphics.drawString((values['date'] ?? '').trim(), bold,
      brush: black, bounds: const Rect.fromLTWH(180.2, 136.6, 379, 14));
  graphics.drawString((values['bidderName'] ?? '').trim(), bold,
      brush: black, bounds: const Rect.fromLTWH(180.2, 150.9, 379, 14));
}
