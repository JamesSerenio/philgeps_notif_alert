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

/// Public entry point; feature parts retain the original drawing operations.
class PdfService {
  const PdfService._();

  static Future<Uint8List> generateBidDocs({
    required Map<String, String> values,
  }) async {
    Future<void> yieldToBrowser() =>
        Future<void>.delayed(const Duration(milliseconds: 1));

    values = values.map(
      (key, value) => MapEntry(key, _pdfSafeText(value)),
    );
    // Explicit global modes take precedence over stale per-section preferences.
    // Calls without a global mode retain the existing section-level API.
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

    // PDF work on Flutter Web shares the UI thread. Yield between the major
    // stages so loading indicators can continue receiving animation frames.
    await yieldToBrowser();

    // Clean replacement for Page 1.
    if (document.pages.count > 0) {
      _drawPageOne(
        document.pages[0],
        values,
      );
    }

    // Page 20 contains the ongoing contracts form.
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

    // Page 21 uses the same editable header and signatory fields. Its table
    // is taller, so the signature block stays below the supporting notes.
    if (document.pages.count > 20) {
      _drawContractStatementPage(
        document.pages[20],
        values,
        signatureTop: 485,
        signatureClearTop: 478,
        businessAddressClearTop: 174,
        businessAddressTop: 176,
      );
      _drawSlccPrivateRow(document.pages[20], values);
    }

    // Rebuild the editable Technical Specifications sheets on genuinely blank
    // pages. Painting white over the bundled rows leaves the old content in
    // the PDF page stream, and external readers can render that stream above
    // the edits even though Chrome's in-app preview looks correct.
    // Page 47 technical specifications header follows the current bid data.
    if (document.pages.count > 46) {
      _drawTechnicalSpecificationsHeader(document.pages[46], values);
    }

    var technicalSpecificationPageCount = 3;
    if (document.pages.count > 48) {
      technicalSpecificationPageCount =
          _drawTechnicalSpecifications(document, values);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // Find the actual Price Schedule section in the source instead of relying
    // on a fixed page number. Some template revisions have blank/form pages
    // immediately before it.
    final priceScheduleStartPage = _findPriceScheduleStartPage(document);
    var priceSchedulePageCount = 1;
    if (priceScheduleStartPage >= 0) {
      priceSchedulePageCount = _drawPriceSchedule(
        document,
        values,
        priceScheduleStartPage,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));

    final bidPriceSummaryStartPage = _findBidPriceSummaryStartPage(document);
    var bidPriceSummaryPageCount = 1;
    if (bidPriceSummaryStartPage >= 0) {
      bidPriceSummaryPageCount = _drawBidPriceSummary(
        document,
        values,
        bidPriceSummaryStartPage,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));

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
    await Future<void>.delayed(const Duration(milliseconds: 1));

    // Other mapped pages, excluding Page 1.
    final mappedFields = PageMapper.mapValuesToPages(values);

    for (final pageEntry in mappedFields.entries) {
      final int pageIndex = pageEntry.key;

      // Page 1 is already handled above.
      if (pageIndex == 0) continue;

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
      // Large bid documents map dozens of pages. Let Flutter Web paint the
      // progress overlay and let Chrome process input between each page.
      await yieldToBrowser();
    }

    await yieldToBrowser();

    // Remove unused continuation templates only after all original page-index
    // mappings have been applied.
    if (scheduleRequirementsStartPage >= 0) {
      for (var pageIndex = (scheduleRequirementsStartPage + 2)
              .clamp(0, document.pages.count - 1)
              .toInt();
          pageIndex >=
              scheduleRequirementsStartPage + scheduleRequirementsPageCount;
          pageIndex--) {
        document.pages.removeAt(pageIndex);
      }
    }
    if (bidPriceSummaryStartPage >= 0) {
      for (var pageIndex = (bidPriceSummaryStartPage + 2)
              .clamp(0, document.pages.count - 1)
              .toInt();
          pageIndex >= bidPriceSummaryStartPage + bidPriceSummaryPageCount;
          pageIndex--) {
        document.pages.removeAt(pageIndex);
      }
    }
    if (priceScheduleStartPage >= 0) {
      for (var pageIndex = (priceScheduleStartPage + 7)
              .clamp(0, document.pages.count - 1)
              .toInt();
          pageIndex >= priceScheduleStartPage + priceSchedulePageCount;
          pageIndex--) {
        document.pages.removeAt(pageIndex);
      }
      // Keep the two Bid Securing Declaration sheets immediately before the
      // Price Schedule. They are required document pages, not unused
      // Technical Specification continuations.
    }
    if (technicalSpecificationPageCount < 3) {
      document.pages.removeAt(48);
    }
    if (technicalSpecificationPageCount < 2) {
      document.pages.removeAt(47);
    }
    await yieldToBrowser();

    final useDeclarationWithTable =
        switch (values['bidSecuringDeclarationTemplate']) {
      'old' => true,
      'without_table' || 'initao_lgu' => false,
      _ => values['bidSecuringDeclarationWithTable'] != 'false',
    };
    if (useDeclarationWithTable) {
      // Locate the original form by its actual text after optional technical
      // pages have been removed, since its final page index can change.
      _drawBidSecuringDeclarationDetails(document, values);
    } else {
      await _replaceBidSecuringDeclarationWithoutTable(document, values);
    }

    await yieldToBrowser();

    // The scanned official receipt is only a sample attachment in the source
    // template and is not required in the generated bid documents.
    if (document.pages.count > 45) {
      document.pages.removeAt(45);
    }

    // Optional generated pages shift the forms that follow them. Locate the
    // Omnibus form by its own title instead of relying on a fixed page index.
    final omnibusPageIndex = _findOmnibusSwornStatementPage(document);
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
        drawInitaoOmnibusNumbering(document, omnibusPageIndex);
      }
    }
    await yieldToBrowser();
    // Run this after mapped fields and optional-page removals so the old
    // signature block cannot be drawn back over the cleaned manpower page.
    _drawManpowerSignature(document, values);
    await yieldToBrowser();
    _drawAfterSalesServiceCertificate(document, values);
    await yieldToBrowser();
    _drawProductWarrantyCertificate(document, values);
    await yieldToBrowser();
    _drawJuratPlaceholders(document, values);
    await yieldToBrowser();
    _drawBidForm(document, values);
    await yieldToBrowser();
    _drawSecretaryCertificate(document, values);
    await yieldToBrowser();

    // Replace the two legacy editable SLCC sheets only after every original
    // page mapping is complete. This keeps all following section indexes
    // stable while the document is being prepared.
    await _replaceSlccSection(document, values);
    await yieldToBrowser();
    await _replaceAfsSection(document);
    await yieldToBrowser();

    // Reverse final PDF pages 29-43 while preserving every page exactly.
    // Export them as templates first, remove the original range, then insert
    // them back in reverse order at the same position.
    if (document.pages.count >= 43) {
      const reverseStartIndex = 28;
      const reversePageCount = 15;
      // Templates created directly from `document` become invalid as soon as
      // their source pages are removed. Reopen a snapshot and keep it alive
      // until all reversed pages have been drawn.
      final snapshotBytes = await document.save();
      final snapshotDocument = PdfDocument(inputBytes: snapshotBytes);
      final reversedTemplates = <({PdfTemplate template, Size size})>[
        for (var index = reverseStartIndex + reversePageCount - 1;
            index >= reverseStartIndex;
            index--)
          (
            template: snapshotDocument.pages[index].createTemplate(),
            size: snapshotDocument.pages[index].size,
          ),
      ];
      for (var page = 0; page < reversePageCount; page++) {
        document.pages.removeAt(reverseStartIndex);
        if (page % 3 == 2) await yieldToBrowser();
      }
      for (var index = 0; index < reversedTemplates.length; index++) {
        final source = reversedTemplates[index];
        final target = document.pages.insert(
          reverseStartIndex + index,
          source.size,
          PdfMargins()..all = 0,
        );
        target.graphics.drawPdfTemplate(
          source.template,
          Offset.zero,
          source.size,
        );
        if (index % 3 == 2) await yieldToBrowser();
      }
      snapshotDocument.dispose();
    }

    // _replaceAfsSection already removes the complete 18-page legacy AFS and
    // attachment range before inserting the clean AFS template. Do not remove
    // fixed page indexes here: the replacement can contain fewer pages, which
    // moves NFCC and Technical Specifications into indexes 43-44 and caused
    // those required sections to be deleted.

    // Remove only the legacy SLCC placeholders before resolving NFCC and
    // Technical Specifications. Doing this after NFCC replacement can make
    // Syncfusion retain stale shifted page references when SLCC is disabled.
    if (values['slccTemplateType']?.trim().toLowerCase() == 'none') {
      _removeSlccSection(document);
      await yieldToBrowser();
    }

    // Resolve and replace NFCC after every optional-page removal. It remains
    // immediately before Technical Specifications, regardless of whether
    // SLCC is present, and neither required section is removed for SLCC=None.
    await _replaceNfccPage(document, values);
    await yieldToBrowser();
    await _moveBusinessPermitBeforeTaxClearance(document);
    await yieldToBrowser();
    await _replacePhilgepsCertificateSection(document);
    await yieldToBrowser();

    if (values['documentTemplateMode'] == 'initao') {
      await _insertInitaoDocumentPages(document, values);
      await yieldToBrowser();
    }

    // Finalize these two generated sections only after every optional page
    // replacement and template insertion. Moving their complete page groups
    // here guarantees Price Schedule then Summary form the PDF ending.
    // These section-specific locators deliberately search the financial-page
    // range. A global title search can match the Table of Contents instead.
    final finalPriceStart = _findPriceScheduleStartPage(document);
    final finalSummaryStart = _findBidPriceSummaryStartPage(document);
    if (finalPriceStart >= 0 && finalSummaryStart > finalPriceStart) {
      await _movePriceAndSummaryToDocumentEnd(
        document,
        priceStart: finalPriceStart,
        summaryStart: finalSummaryStart,
        priceSchedulePageCount: priceSchedulePageCount,
        summaryPageCount: bidPriceSummaryPageCount,
      );
      await yieldToBrowser();
    }
    // Keep Syncfusion's normal incremental output here. Chrome/PDFium resolves
    // this revision correctly; the Railway compatibility service flattens its
    // visible overlays into permanent page content for the other readers.
    final List<int> outputBytes = await document.save();
    document.dispose();
    return Uint8List.fromList(outputBytes);
  }
}
