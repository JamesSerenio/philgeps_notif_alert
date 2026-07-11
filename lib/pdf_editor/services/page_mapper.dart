import '../data/page_mapping.dart';
import '../models/pdf_field.dart';

class PageMapper {
  const PageMapper._();

  static PdfField? getFieldByKey(String key) {
    for (final field in bidDocsFields) {
      if (field.key == key) {
        return field;
      }
    }

    return null;
  }

  static List<PdfFieldPosition> getPositions(String key) {
    final field = getFieldByKey(key);

    if (field == null) {
      return const [];
    }

    return field.positions;
  }

  static Map<int, List<PdfField>> groupFieldsByPage() {
    final Map<int, List<PdfField>> grouped = {};

    for (final field in bidDocsFields) {
      for (final position in field.positions) {
        grouped.putIfAbsent(position.pageIndex, () => []);

        final fieldsOnPage = grouped[position.pageIndex]!;

        final alreadyAdded = fieldsOnPage.any(
          (existingField) => existingField.key == field.key,
        );

        if (!alreadyAdded) {
          fieldsOnPage.add(field);
        }
      }
    }

    return grouped;
  }

  static Map<int, List<MappedPdfField>> mapValuesToPages(
    Map<String, String> values,
  ) {
    final Map<int, List<MappedPdfField>> result = {};

    for (final field in bidDocsFields) {
      final value = values[field.key]?.trim() ?? '';

      if (value.isEmpty) {
        continue;
      }

      for (final position in field.positions) {
        result.putIfAbsent(position.pageIndex, () => []);

        result[position.pageIndex]!.add(
          MappedPdfField(
            field: field,
            position: position,
            value: value,
          ),
        );
      }
    }

    return result;
  }
}

class MappedPdfField {
  final PdfField field;
  final PdfFieldPosition position;
  final String value;

  const MappedPdfField({
    required this.field,
    required this.position,
    required this.value,
  });
}
