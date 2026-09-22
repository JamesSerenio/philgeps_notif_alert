part of '../screens/pdf_editor_screen.dart';

class _TechnicalSpecificationEntry {
  _TechnicalSpecificationEntry({
    String specification = '',
    String quantity = '',
    String unit = '',
    String parameter = '',
    PricingQuantity? pricingQuantity,
  })  : specification = TextEditingController(text: specification),
        quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        parameter = TextEditingController(text: parameter),
        hasParameter = parameter.trim().isNotEmpty,
        pricingQuantity =
            pricingQuantity ?? PricingQuantity.fromInput(quantity) {
    _lastQuantityText = quantity;
    this.quantity.addListener(_updateQuantity);
  }

  PricingQuantity pricingQuantity;
  late String _lastQuantityText;
  void _updateQuantity() {
    if (quantity.text == _lastQuantityText) return;
    _lastQuantityText = quantity.text;
    pricingQuantity = PricingQuantity.fromInput(quantity.text);
  }

  Map<String, Object> toMap() => {
        'specification': specification.text.trim(),
        'quantity': quantity.text.trim(),
        'unit': unit.text.trim(),
        'parameter': parameter.text.trim(),
        ...pricingQuantity.toMap(),
      };

  final TextEditingController specification;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController parameter;
  bool hasParameter;
  final FocusNode unitFocusNode = FocusNode();

  List<TextEditingController> get controllers =>
      [specification, quantity, unit, parameter];

  void dispose() {
    specification.dispose();
    quantity.dispose();
    unit.dispose();
    parameter.dispose();
    unitFocusNode.dispose();
  }
}

class _PriceScheduleEntry {
  _PriceScheduleEntry({String totalPricePerUnit = '', String deduction = ''})
      : totalPricePerUnit = TextEditingController(text: totalPricePerUnit),
        deduction = TextEditingController(text: deduction);

  final TextEditingController totalPricePerUnit;
  final TextEditingController deduction;

  void dispose() {
    totalPricePerUnit.dispose();
    deduction.dispose();
  }
}
