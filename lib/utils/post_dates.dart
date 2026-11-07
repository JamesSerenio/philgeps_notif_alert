// Dates without offsets on PhilGEPS represent Philippine time (UTC+08).
DateTime? parsePhilgepsDate(String? value) {
  var text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    text += 'T00:00:00+08:00';
  } else if (!RegExp(
    r'(Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  ).hasMatch(text)) {
    text = text.replaceFirst(' ', 'T') + '+08:00';
  }
  return DateTime.tryParse(text)?.toUtc();
}

bool discoveredWithin24Hours(DateTime? discoveredAt, {DateTime? now}) {
  if (discoveredAt == null) return false;
  final age = (now ?? DateTime.now()).toUtc().difference(discoveredAt.toUtc());
  return !age.isNegative && age < const Duration(hours: 24);
}

DateTime philippineTime(DateTime value) =>
    value.toUtc().add(const Duration(hours: 8));
