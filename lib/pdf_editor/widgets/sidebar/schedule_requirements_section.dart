part of '../../screens/pdf_editor_screen.dart';

extension _ScheduleRequirementsSection on _PdfEditorScreenState {
  Widget scheduleRequirementsFields() {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      backgroundColor: Colors.white,
      collapsedBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFD8E1DB)),
      ),
      leading: const Icon(
        Icons.local_shipping_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'Schedule of Requirements',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        isLoadingScheduleRequirements
            ? 'Loading from PhilGEPS...'
            : isSavingScheduleRequirements
                ? 'Saving manual correction...'
                : deliveredWeeksMonthsController.text.trim().isEmpty
                    ? 'No Delivery Period found in PhilGEPS'
                    : 'Auto-filled from PhilGEPS • Editable',
      ),
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: const Color(0xFF0B5D3B),
          value: includeTotalInScheduleRequirements,
          title: const Text(
            'Include Total column',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Merge Qty and Unit, then show Total Price Delivered Final Destination.',
            style: TextStyle(fontSize: 11.5),
          ),
          onChanged: (value) {
            _updateState(() {
              includeTotalInScheduleRequirements = value ?? false;
            });
            _invalidateGeneratedPdf();
          },
        ),
        formField(
          label: 'Delivery Period (PhilGEPS)',
          controller: deliveredWeeksMonthsController,
          maxLines: 2,
        ),
        const Text(
          'This delivery schedule applies to all Technical Specification items.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF68736D)),
        ),
      ],
    );
  }
}
