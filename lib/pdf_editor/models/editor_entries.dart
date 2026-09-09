part of '../screens/pdf_editor_screen.dart';

class _TechnicalSpecificationEntry {
  _TechnicalSpecificationEntry({
    String specification = '',
    String quantity = '',
    String unit = '',
    String parameter = '',
  })  : specification = TextEditingController(text: specification),
        quantity = TextEditingController(text: quantity),
        unit = TextEditingController(text: unit),
        parameter = TextEditingController(text: parameter),
        hasParameter = parameter.trim().isNotEmpty;

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
