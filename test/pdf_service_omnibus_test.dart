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
        'projectTitle':
            'PROCUREMENT OF 12-CHANNEL CCTV PACKAGE WITH INCLUSIVE INSTALLATION SERVICES',
        'procuringEntity': 'MUNICIPALITY OF VILLANUEVA, MISAMIS ORIENTAL',
        'technicalSpecifications': '[]',
        'priceSchedule': '[]',
      },
    );
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();
    final compactText = text.replaceAll(RegExp(r'\s+'), '');

    expect(compactText, contains('CarlosRafaelA.Jamilo'));
    expect(
        compactText, contains('SitioPuli,Carmen,CagayandeOro.MisamisOriental'));
    expect(compactText, contains('PROCUREMENTOF12-CHANNELCCTVPACKAGE'));
    expect(compactText, contains('MUNICIPALITYOFVILLANUEVA,MISAMISORIENTAL'));
  });
}
