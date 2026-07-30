import 'package:flutter_test/flutter_test.dart';
import 'package:philgeps_notif_alert/pdf_editor/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the selected signatory on the Omnibus Sworn Statement', () async {
    final bytes = await PdfService.generateBidDocs(
      values: const {
        'submittedBy': 'CARLOS RAFAEL A. JAMILO',
        'technicalSpecifications': '[]',
        'priceSchedule': '[]',
      },
    );
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains('Carlos Rafael A. Jamilo'));
    expect(text, contains('Camaman-an, Cagayan de Oro City'));
  });
}
