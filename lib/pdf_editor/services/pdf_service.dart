import '../models/item_pricing.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'page_mapper.dart';
import 'initao_omnibus_numbering.dart';

part 'pdf/pdf_page_service.dart';
part 'pdf/pdf_document_template_service.dart';
part 'pdf/pdf_financial_service.dart';
part 'pdf/pdf_slcc_service.dart';
part 'pdf/pdf_text_service.dart';
part 'pdf/pdf_field_service.dart';
part 'pdf/pdf_bid_security_service.dart';
part 'pdf/pdf_bid_security_legacy_service.dart';
part 'pdf/pdf_technical_specs_service.dart';
part 'pdf/pdf_price_schedule_service.dart';
part 'pdf/pdf_omnibus_service.dart';
part 'pdf/pdf_certificate_service.dart';
part 'pdf/pdf_jurat_service.dart';
part 'pdf/pdf_bid_form_service.dart';
part 'pdf/pdf_secretary_certificate_service.dart';
part 'pdf/pdf_schedule_requirements_service.dart';
part 'pdf/pdf_bid_price_summary_service.dart';

/// Structural location of the inserted AFS block.
///
/// IMPORTANT:
/// [startIndex] is valid only while no page before the AFS block is
/// inserted, removed, or moved.
///
/// Therefore the production generation flow captures this placement only
/// after all earlier structural changes have completed.
class _AfsPlacement {
  const _AfsPlacement({
    required this.startIndex,
    required this.pageCount,
  });

  final int startIndex;
  final int pageCount;

  int get endExclusive => startIndex + pageCount;

  bool isValidFor(PdfDocument document) =>
      startIndex >= 0 && pageCount > 0 && endExclusive <= document.pages.count;
}

int _findRealPdfSectionPage(
  PdfDocument document,
  String normalizedTitle,
) {
  final extractor = PdfTextExtractor(document);
  for (var pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
    final normalized = extractor
        .extractText(startPageIndex: pageIndex, endPageIndex: pageIndex)
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (normalized.contains('CHECKLISTOFELIGIBILITYREQUIREMENTSFORGOODS') ||
        normalized.contains('TABLEOFCONTENTS')) {
      continue;
    }
    if (normalized.contains(normalizedTitle)) return pageIndex;
  }
  return -1;
}

/// Public entry point; feature parts retain the original drawing operations.
class PdfService {
  const PdfService._();

  static Future<Uint8List> generateBidDocs({
    required Map<String, String> values,
  }) async {
    Future<void> yieldToBrowser() =>
        Future<void>.delayed(const Duration(milliseconds: 1));

    await _ensurePdfUnicodeMarkerFont();

    values = values.map(
      (key, value) => MapEntry(
        key,
        _pdfSafeText(value),
      ),
    );

    if (values.containsKey('documentTemplateMode')) {
      final initao = values['documentTemplateMode'] == 'initao';

      values['omnibusTemplateType'] = initao ? 'initao_lgu' : 'old';

      values['bidSecuringDeclarationTemplate'] = initao
          ? 'initao_lgu'
          : values['bidSecuringDeclarationTemplate'] == 'without_table'
              ? 'without_table'
              : 'old';
    }

    final ByteData templateData = await rootBundle.load(
      'assets/pdf/bidocs_template.pdf',
    );

    final Uint8List templateBytes = templateData.buffer.asUint8List();

    final PdfDocument document = PdfDocument(
      inputBytes: templateBytes,
    );

    await yieldToBrowser();

    // ============================================================
    // PAGE 1
    // ============================================================

    if (document.pages.count > 0) {
      _drawPageOne(
        document.pages[0],
        values,
      );
    }

    // ============================================================
    // ONGOING CONTRACTS
    // ============================================================

    if (document.pages.count > 19) {
      _drawContractStatementPage(
        document.pages[19],
        values,
        signatureTop: 428,
        signatureClearTop: 410,
        businessAddressClearTop: 210,
        businessAddressTop: 212,
      );
    }

    if (document.pages.count > 20) {
      _drawContractStatementPage(
        document.pages[20],
        values,
        signatureTop: 485,
        signatureClearTop: 478,
        businessAddressClearTop: 174,
        businessAddressTop: 176,
      );

      _drawSlccPrivateRow(
        document.pages[20],
        values,
      );
    }

    // ============================================================
    // TECHNICAL SPECIFICATIONS
    // ============================================================

    // This is the dedicated three-page Technical Specifications allocation in
    // the master. It is not a final PDF page number: no page has been removed
    // before the renderer or its section-owned cleanup runs.
    const technicalSpecificationsStartPage = 46;

    if (document.pages.count > technicalSpecificationsStartPage) {
      _drawTechnicalSpecificationsHeader(
        document.pages[technicalSpecificationsStartPage],
        values,
      );
    }

    var technicalSpecificationPageCount = 3;

    if (document.pages.count > technicalSpecificationsStartPage + 2) {
      technicalSpecificationPageCount = _drawTechnicalSpecifications(
        document,
        values,
      );
    }
    print(
      'PDF PAGE COUNT after Technical Specs render: '
      '${document.pages.count}',
    );

    await yieldToBrowser();

    // ============================================================
    // PRICE SCHEDULE
    // ============================================================

    final priceScheduleStartPage = _findPriceScheduleStartPage(document);

    var priceSchedulePageCount = 1;

    if (priceScheduleStartPage >= 0) {
      priceSchedulePageCount = _drawPriceSchedule(
        document,
        values,
        priceScheduleStartPage,
      );
    }
    print(
      'PDF PAGE COUNT after Price Schedule render: '
      '${document.pages.count}',
    );

    await yieldToBrowser();

    // ============================================================
    // SUMMARY OF BID PRICES
    // ============================================================

    final bidPriceSummaryStartPage = _findBidPriceSummaryStartPage(document);

    var bidPriceSummaryPageCount = 1;

    if (bidPriceSummaryStartPage >= 0) {
      bidPriceSummaryPageCount = _drawBidPriceSummary(
        document,
        values,
        bidPriceSummaryStartPage,
      );
    }
    print(
      'PDF PAGE COUNT after Summary render: ${document.pages.count}',
    );

    await yieldToBrowser();

    // ============================================================
    // SCHEDULE OF REQUIREMENTS
    // ============================================================

    final scheduleRequirementsStartPage =
        _findScheduleRequirementsStartPage(document);

    var scheduleRequirementsPageCount = 1;

    if (scheduleRequirementsStartPage >= 0) {
      scheduleRequirementsPageCount = _drawScheduleRequirements(
        document,
        values,
        scheduleRequirementsStartPage,
      );
    }
    print(
      'PDF PAGE COUNT after Schedule Requirements render: '
      '${document.pages.count}',
    );

    await yieldToBrowser();

    // ============================================================
    // OTHER MAPPED FIELDS
    // ============================================================

    final mappedFields = PageMapper.mapValuesToPages(values);

    for (final pageEntry in mappedFields.entries) {
      final int pageIndex = pageEntry.key;

      if (pageIndex == 0) {
        continue;
      }

      if (pageIndex < 0 || pageIndex >= document.pages.count) {
        continue;
      }

      final PdfPage page = document.pages[pageIndex];

      for (final mappedField in pageEntry.value) {
        final Rect bounds = mappedField.position.bounds;

        page.graphics.drawRectangle(
          brush: PdfSolidBrush(
            PdfColor(255, 255, 255),
          ),
          bounds: Rect.fromLTWH(
            bounds.left - 3,
            bounds.top - 2,
            bounds.width + 6,
            bounds.height + 4,
          ),
        );

        final PdfFont font = PdfStandardFont(
          PdfFontFamily.timesRoman,
          mappedField.field.fontSize,
          style: mappedField.field.isBold
              ? PdfFontStyle.bold
              : PdfFontStyle.regular,
        );

        page.graphics.drawString(
          mappedField.value,
          font,
          bounds: bounds,
          format: PdfStringFormat(
            alignment: PdfTextAlignment.left,
            lineAlignment: PdfVerticalAlignment.top,
            wordWrap: PdfWordWrapType.word,
          ),
        );
      }

      await yieldToBrowser();
    }

    await yieldToBrowser();

    // ============================================================
    // REMOVE UNUSED DYNAMIC CONTINUATION TEMPLATES
    // ============================================================
    //
    // Each renderer owns only its bundled continuation allocation.  Remove
    // the unused tail in reverse document order, so an earlier section never
    // relies on a page index shifted by cleanup of a later section.
    //
    // Do not use extracted text here. These are known renderer-owned template
    // slots, while scanned/supporting pages remain untouched.
    // ============================================================

    _removeUnusedSectionTemplatePages(
      document,
      sectionName: 'Schedule of Requirements',
      startPageIndex: scheduleRequirementsStartPage,
      allocatedPages: 3,
      usedPages: scheduleRequirementsPageCount,
    );
    _removeUnusedSectionTemplatePages(
      document,
      sectionName: 'Summary of Bid Prices',
      startPageIndex: bidPriceSummaryStartPage,
      allocatedPages: 3,
      usedPages: bidPriceSummaryPageCount,
    );
    _removeUnusedSectionTemplatePages(
      document,
      sectionName: 'Price Schedule for Goods',
      startPageIndex: priceScheduleStartPage,
      allocatedPages: 8,
      usedPages: priceSchedulePageCount,
    );
    _removeUnusedSectionTemplatePages(
      document,
      sectionName: 'Technical Specifications',
      startPageIndex: technicalSpecificationsStartPage,
      allocatedPages: 3,
      usedPages: technicalSpecificationPageCount,
    );
    print(
      'PDF PAGE COUNT after dynamic continuation cleanup: '
      '${document.pages.count}',
    );

    await yieldToBrowser();

    // ============================================================
    // BID SECURING DECLARATION
    // ============================================================

    final useDeclarationWithTable =
        switch (values['bidSecuringDeclarationTemplate']) {
      'old' => true,
      'without_table' || 'initao_lgu' => false,
      _ => values['bidSecuringDeclarationWithTable'] != 'false',
    };

    if (useDeclarationWithTable) {
      _drawBidSecuringDeclarationDetails(
        document,
        values,
      );
    } else {
      await _replaceBidSecuringDeclarationWithoutTable(
        document,
        values,
      );
    }

    await yieldToBrowser();

    // ============================================================
    // IMPORTANT:
    // NO FIXED PAGE DELETION HERE
    // ============================================================

    // ============================================================
    // OMNIBUS
    // ============================================================

    final omnibusPageIndex = _findOmnibusSwornStatementPage(
      document,
    );

    if (omnibusPageIndex >= 0) {
      _drawOmnibusSwornStatementIdentity(
        document,
        values,
        pageIndex: omnibusPageIndex,
      );

      _drawOmnibusSwornStatementLastPage(
        document,
        values,
        pageIndex: omnibusPageIndex + 1,
      );

      if (values['omnibusTemplateType'] == 'initao_lgu') {
        drawInitaoOmnibusNumbering(
          document,
          omnibusPageIndex,
        );
      }
    }

    await yieldToBrowser();

    // ============================================================
    // OTHER DYNAMIC SECTIONS
    // ============================================================

    _drawManpowerSignature(
      document,
      values,
    );

    await yieldToBrowser();

    _drawAfterSalesServiceCertificate(
      document,
      values,
    );

    await yieldToBrowser();

    _drawProductWarrantyCertificate(
      document,
      values,
    );

    await yieldToBrowser();

    _drawJuratPlaceholders(
      document,
      values,
    );

    await yieldToBrowser();

    _drawBidForm(
      document,
      values,
    );

    await yieldToBrowser();

    _drawSecretaryCertificate(
      document,
      values,
    );

    await yieldToBrowser();

    // ============================================================
    // FINAL STRUCTURAL PHASE
    // ============================================================

    // ============================================================
    // SLCC
    // ============================================================

    await _replaceSlccSection(
      document,
      values,
    );

    await yieldToBrowser();

    if (values['slccTemplateType']?.trim().toLowerCase() == 'none') {
      _removeSlccSection(
        document,
      );

      await yieldToBrowser();
    }

    // ============================================================
    // NFCC
    // ============================================================

    await _replaceNfccPage(
      document,
      values,
    );

    await yieldToBrowser();

    // ============================================================
    // BUSINESS PERMIT / TAX CLEARANCE
    // ============================================================

    await _moveBusinessPermitBeforeTaxClearance(
      document,
    );

    await yieldToBrowser();

    // ============================================================
    // AFS
    // ============================================================

    var afsPlacement = _validateAfsPlacement(
      document,
      await _replaceAfsSection(
        document,
      ),
    );

    await yieldToBrowser();

    // ============================================================
    // PHILGEPS CERTIFICATE
    // ============================================================

    final pageCountBeforePhilgepsReplacement = document.pages.count;

    await _replacePhilgepsCertificateSection(
      document,
    );

    await yieldToBrowser();

    final pageCountAfterPhilgepsReplacement = document.pages.count;

    if (pageCountAfterPhilgepsReplacement !=
        pageCountBeforePhilgepsReplacement) {
      throw StateError(
        'PhilGEPS replacement changed document page count after AFS '
        'placement was captured. '
        'before=$pageCountBeforePhilgepsReplacement '
        'after=$pageCountAfterPhilgepsReplacement '
        'afsStart=${afsPlacement.startIndex} '
        'afsEnd=${afsPlacement.endExclusive}.',
      );
    }

    afsPlacement = await _removeLegacyAfsFrontMatterAfterPhilgeps(
      document,
      afsPlacement,
    );

    _validateAfsPlacement(
      document,
      afsPlacement,
    );

    // ============================================================
    // REQUIRED PAGE INTEGRITY CHECK
    // ============================================================

    _validateStatementOfOngoingPresent(
      document,
    );

    // ============================================================
    // INITAO FINAL REORDERING
    // ============================================================

    if (values['documentTemplateMode'] == 'initao') {
      await _insertInitaoDocumentPages(
        document,
        values,
        afsPlacement,
      );

      await yieldToBrowser();
    } else {
      _validateAfsPlacement(
        document,
        afsPlacement,
      );
    }

    // ============================================================
    // FINAL SAVE
    // ============================================================

    final List<int> outputBytes = await document.save();

    document.dispose();

    return Uint8List.fromList(
      outputBytes,
    );
  }
}

/// Fail immediately only if Statement of Ongoing disappears entirely.
///
/// IMPORTANT:
/// The Ongoing Contracts section may occupy MORE THAN ONE PAGE.
/// Therefore 2 detected pages is valid.
void _validateStatementOfOngoingPresent(
  PdfDocument document,
) {
  if (document.pages.count == 0) {
    throw StateError(
      'Statement of Ongoing Contracts integrity failure: document is empty.',
    );
  }

  final extractor = PdfTextExtractor(document);

  final ongoingPages = <int>[];

  for (var pageIndex = 0; pageIndex < document.pages.count; pageIndex++) {
    final text = extractor
        .extractText(
          startPageIndex: pageIndex,
          endPageIndex: pageIndex,
        )
        .replaceAll(
          '\u0000',
          '',
        )
        .replaceAll(
          RegExp(r'\s+'),
          '',
        )
        .toUpperCase();

    if (text.contains(
      'STATEMENTOFALLITSONGOING',
    )) {
      ongoingPages.add(
        pageIndex,
      );
    }
  }

  if (ongoingPages.isEmpty) {
    throw StateError(
      'Statement of Ongoing Contracts integrity failure: '
      'no Ongoing Contracts page exists before final document ordering. '
      'documentPages=${document.pages.count}.',
    );
  }

  for (final pageIndex in ongoingPages) {
    if (pageIndex < 0 || pageIndex >= document.pages.count) {
      throw StateError(
        'Statement of Ongoing Contracts integrity failure: '
        'invalid page index=$pageIndex '
        'documentPages=${document.pages.count}.',
      );
    }
  }
}

/// Validate the structural AFS placement.
_AfsPlacement _validateAfsPlacement(
  PdfDocument document,
  _AfsPlacement? placement,
) {
  if (placement == null || !placement.isValidFor(document)) {
    throw StateError(
      'AFS replacement failed or returned invalid placement.',
    );
  }

  final afsStart = placement.startIndex;

  final afsEndExclusive = placement.endExclusive;

  final firstAfsPageMissing = afsStart >= document.pages.count;

  final secondAfsPageMissing = afsStart + 1 >= document.pages.count;

  if (placement.pageCount != 15 ||
      firstAfsPageMissing ||
      secondAfsPageMissing ||
      afsEndExclusive > document.pages.count) {
    throw StateError(
      'AFS integrity failure: '
      'expected=15 '
      'actual=${placement.pageCount} '
      'missing first AFS page=$firstAfsPageMissing '
      'missing second AFS page=$secondAfsPageMissing '
      'start=$afsStart '
      'end=$afsEndExclusive '
      'documentPages=${document.pages.count}.',
    );
  }

  return placement;
}
