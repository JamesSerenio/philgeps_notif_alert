import 'dart:typed_data';

import 'package:http/http.dart' as http;

class PdfImageFinalizerService {
  const PdfImageFinalizerService._();

  static const String _endpoint =
      'https://philgepsnotifalert-production.up.railway.app/render-compatible-pdf';

  static Future<Uint8List> finalizeAsImages(
    Uint8List editedPdfBytes,
  ) async {
    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/pdf',
      },
      body: editedPdfBytes,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'PDF image finalization failed. '
        'Status: ${response.statusCode}',
      );
    }

    return response.bodyBytes;
  }
}