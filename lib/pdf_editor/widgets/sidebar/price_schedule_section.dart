part of '../../screens/pdf_editor_screen.dart';

extension _PriceScheduleSection on _PdfEditorScreenState {
  ItemPricing _itemPricing(int index) => ItemPricing(
        quantity: technicalSpecifications[index].pricingQuantity,
        unitPrice:
            parseCurrency(priceScheduleEntries[index].totalPricePerUnit.text),
        deduction: parseCurrency(priceScheduleEntries[index].deduction.text),
      );

  String _money(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$grouped.${parts.last}';
  }

  Widget priceScheduleFields() {
    return _SidebarAccordion(
      leading: const Icon(Icons.payments_outlined, color: Color(0xFF0B5D3B)),
      title: const Text(
        'PRICE SCHEDULE FOR GOODS',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingPriceSchedule
            ? 'Loading saved values...'
            : isSavingPriceSchedule
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        if (technicalSpecifications.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Add items under TECHNICAL SPECIFICATIONS first.'),
          ),
        for (var index = 0; index < technicalSpecifications.length; index++)
          Builder(builder: (context) {
            final specification = technicalSpecifications[index];
            final price = priceScheduleEntries[index];
            final calculation = _itemPricing(index);
            final breakdown = [
              calculation.adjustedUnitPrice,
              calculation.unitPriceComponent,
              calculation.transportInsuranceComponent,
              calculation.taxComponent,
              calculation.totalDeliveredPrice
            ];
            String amount(int column) => _money(breakdown[column]);
            Widget priceRow(String label, String value) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Card(
              elevation: 0,
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFD7E3DC)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B5D3B),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'ITEM ${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${specification.quantity.text} ${specification.unit.text}',
                          style: const TextStyle(
                            color: Color(0xFF526159),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      specification.specification.text.isEmpty
                          ? 'No specification entered'
                          : specification.specification.text,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: price.totalPricePerUnit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [
                        _ThousandsSeparatorInputFormatter(),
                      ],
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        labelText: 'Total Price per Unit',
                        prefixText: '₱ ',
                        helperText: 'Enter the 100% unit price',
                        filled: true,
                        fillColor: const Color(0xFFF5FAF7),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: price.deduction,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: const [
                        _ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Deduction',
                        prefixText: '− ₱ ',
                        helperText: 'Optional amount deducted from unit price',
                        filled: true,
                        fillColor: const Color(0xFFFFF7F2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    priceRow('Adjusted Total Price per Unit', amount(0)),
                    priceRow('Unit Price/Item (50%)', amount(1)),
                    priceRow(
                      'Transportation & Insurance (20%)',
                      amount(2),
                    ),
                    priceRow(
                      'Sales & Other Taxes (30%)',
                      amount(3),
                    ),
                    const Divider(height: 20),
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F4ED),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TOTAL DELIVERED PRICE',
                            style: TextStyle(
                              color: Color(0xFF38634D),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: .4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '₱ ${amount(4)}',
                            style: const TextStyle(
                              color: Color(0xFF0B5D3B),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        if (technicalSpecifications.isNotEmpty)
          Text(
              'Grand Total: \u20b1 ${_money(List.generate(technicalSpecifications.length, (index) => _itemPricing(index).totalDeliveredPrice).fold<double>(0, (sum, value) => sum + value))}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
