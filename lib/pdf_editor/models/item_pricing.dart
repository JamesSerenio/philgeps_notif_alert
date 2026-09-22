/// Normalize currency input once; calculations use numeric values only.
double parseCurrency(Object? value) {
  final parsed = double.tryParse((value ?? '')
      .toString()
      .replaceAll('\u20b1', '')
      .replaceAll(',', '')
      .trim());
  return parsed != null && parsed.isFinite ? parsed : 0;
}

enum PricingType { material, equipmentDaily }

class PricingQuantity {
  const PricingQuantity(this.quantity,
      {this.numberOfDays = 1, this.type = PricingType.material});
  final double quantity;
  final double numberOfDays;
  final PricingType type;
  double get effectiveQuantity =>
      quantity * (type == PricingType.equipmentDaily ? numberOfDays : 1);

  /// Input/legacy-data boundary only, never a rendered card/PDF string.
  /// Kept here so existing saved compound Qty inputs migrate without data loss.
  factory PricingQuantity.fromInput(String input) {
    final normalized = input.replaceAll(',', '').trim();
    final compound = RegExp(
            r'^(\d+(?:\.\d+)?)\s*(?:units?)?\s*[x\u00d7*]\s*(\d+(?:\.\d+)?)\s*days?(?:\s+units?)?$',
            caseSensitive: false)
        .firstMatch(normalized);
    if (compound != null) {
      return PricingQuantity(parseCurrency(compound.group(1)),
          numberOfDays: parseCurrency(compound.group(2)),
          type: PricingType.equipmentDaily);
    }
    final quantity =
        RegExp(r'^(\d+(?:\.\d+)?)(?:\s+[^\d]*)?$').firstMatch(normalized);
    return PricingQuantity(parseCurrency(quantity?.group(1)));
  }

  factory PricingQuantity.fromMap(Map value) {
    if (value['quantityValue'] == null) {
      return PricingQuantity.fromInput((value['quantity'] ?? '').toString());
    }
    return PricingQuantity(parseCurrency(value['quantityValue']),
        numberOfDays: parseCurrency(value['numberOfDays'] ?? 1),
        type: value['pricingType'] == 'equipmentDaily'
            ? PricingType.equipmentDaily
            : PricingType.material);
  }

  Map<String, Object> toMap() => {
        'quantityValue': quantity,
        'numberOfDays': numberOfDays,
        'pricingType': type.name,
      };
}

class ItemPricing {
  ItemPricing(
      {required this.quantity, required double unitPrice, double deduction = 0})
      : adjustedUnitPrice = _cents(
            (unitPrice - deduction).clamp(0, double.infinity).toDouble());
  final PricingQuantity quantity;
  final double adjustedUnitPrice;
  double get effectiveQuantity => quantity.effectiveQuantity;
  double get unitPriceComponent => _cents(adjustedUnitPrice * .50);
  double get transportInsuranceComponent => _cents(adjustedUnitPrice * .20);
  double get taxComponent => _cents(
      adjustedUnitPrice - unitPriceComponent - transportInsuranceComponent);
  double get calculatedTotal => _cents(adjustedUnitPrice * effectiveQuantity);
  double get totalDeliveredPrice => calculatedTotal;
  static double _cents(double value) => (value * 100).round() / 100;

  factory ItemPricing.fromMaps(Map specification, Map price) => ItemPricing(
        quantity: PricingQuantity.fromMap(specification),
        unitPrice: parseCurrency(price['totalPricePerUnit']),
        deduction: parseCurrency(price['deduction']),
      );
}
