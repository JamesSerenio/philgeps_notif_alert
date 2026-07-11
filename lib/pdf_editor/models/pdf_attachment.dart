import 'dart:typed_data';

class PdfAttachment {
  final String id;
  final String name;
  final Uint8List bytes;
  final String type;

  const PdfAttachment({
    required this.id,
    required this.name,
    required this.bytes,
    required this.type,
  });

  bool get isImage {
    return type == 'jpg' || type == 'jpeg' || type == 'png' || type == 'webp';
  }

  bool get isPdf {
    return type == 'pdf';
  }
}
