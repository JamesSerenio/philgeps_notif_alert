import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the selected signatory on the Omnibus Sworn Statement', () async {
    final bytes = await PdfService.generateBidDocs(
      values: const {
        'submittedBy': 'CARLOS RAFAEL A. JAMILO',
        'submittedByFormalName': 'Carlos Rafael A. Jamilo',
        'submittedByCivilStatus': 'single',
        'submittedByAddress':
            'Camaman-an, Cagayan de Oro City, Misamis Oriental',
        'bidderName': 'MIKATA PRIME CORPORATION',
        'municipality': 'Sumilao',
        'date': 'August 11, 2026',
        'bidSecuringDeclarationWithTable': 'true',
        'projectTitle':
            'PROCUREMENT OF 12-CHANNEL CCTV PACKAGE WITH INCLUSIVE INSTALLATION SERVICES',
        'procuringEntity': 'MUNICIPALITY OF VILLANUEVA, MISAMIS ORIENTAL',
        'technicalSpecifications': '[]',
        'priceSchedule': '[]',
      },
    );
    final document = PdfDocument(inputBytes: bytes);
    final declarationPageIndex = PdfTextExtractor(document)
        .extractTextLines()
        .firstWhere(
          (line) =>
              line.text.toUpperCase().contains('BID SECURING DECLARATION'),
        )
        .pageIndex;
    final declarationSignatureText = PdfTextExtractor(document)
        .extractText(
          startPageIndex: declarationPageIndex + 1,
          endPageIndex: declarationPageIndex + 1,
        )
        .replaceAll(RegExp(r'\s+'), '');
    final text = PdfTextExtractor(document).extractText();
    document.dispose();
    final compactText = text.replaceAll(RegExp(r'\s+'), '');

    expect(compactText, contains('CarlosRafaelA.Jamilo'));
    expect(
        compactText, contains('SitioPuli,Carmen,CagayandeOro.MisamisOriental'));
    expect(compactText, contains('PROCUREMENTOF12-CHANNELCCTVPACKAGE'));
    expect(compactText, contains('MUNICIPALITYOFVILLANUEVA,MISAMISORIENTAL'));
    expect(compactText, contains('MunicipalityofSumilao'));
    expect(compactText, contains('August11,2026'));
    expect(declarationSignatureText, contains('CarlosRafaelA.Jamilo'));
    expect(declarationSignatureText, contains('August11,2026'));
    expect(declarationSignatureText, contains('MunicipalityofSumilao'));
    expect(declarationSignatureText.toUpperCase(), isNot(contains('JURAT')));
  });

  test('replaces the bid securing declaration with the no-table template',
      () async {
    final bytes = await PdfService.generateBidDocs(
      values: const {
        'province': 'Bukidnon',
        'municipality': 'Impasugong',
        'referenceNumber': '13118796',
        'procuringEntity': 'MUNICIPALITY OF IMPASUGONG, BUKIDNON',
        'date': 'July 20, 2026',
        'bidderName': 'MIKATA PRIME CORPORATION',
        'submittedBy': 'JHO ANN Q, CLEOPAS',
        'submittedByFormalName': 'Jho Ann Q. Cleopas',
        'technicalSpecifications': '[]',
        'priceSchedule': '[]',
        'bidSecuringDeclarationWithTable': 'false',
      },
    );
    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);
    final compactText =
        extractor.extractText().replaceAll(RegExp(r'\s+'), '');
    final declarationPageIndex = extractor
        .extractTextLines()
        .firstWhere(
          (line) =>
              line.text.toUpperCase().contains('BID SECURING DECLARATION'),
        )
        .pageIndex;
    final declarationSignatureText = extractor
        .extractText(
          startPageIndex: declarationPageIndex + 1,
          endPageIndex: declarationPageIndex + 1,
        )
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    final pageCount = document.pages.count;
    document.dispose();

    expect(pageCount, 61);
    expect(compactText, contains('ProjectIdentificationNo.:13118796'));
    // Covered template text remains in the PDF extraction stream even though
    // it is no longer visible, so verify the newly drawn recipient separately.
    expect(compactText, contains('MUNICIPALITYOFIMPASUGONG,BUKIDNON'));
    expect(compactText, contains('MunicipalityofImpasugong'));
    expect(compactText, contains('JhoAnnQ.Cleopas'));
    expect(compactText, contains('July20,2026'));
    expect(declarationSignatureText, contains('JURAT'));
    expect(declarationSignatureText, contains('JHOANNQ.CLEOPAS'));
    expect(declarationSignatureText, contains('JULY20,2026'));
  });
}
