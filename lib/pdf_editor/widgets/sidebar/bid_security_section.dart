part of '../../screens/pdf_editor_screen.dart';

extension _BidSecuritySection on _PdfEditorScreenState {
  Widget bidSecuringDeclarationFields() {
    return _SidebarAccordion(
      leading: const Icon(
        Icons.security_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'BID SECURING DECLARATION',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        bidSecuritySaveError ??
            (isLoadingBidSecurity
                ? 'Loading saved values...'
                : isSavingBidSecurity
                    ? 'Saving...'
                    : 'Saved automatically'),
      ),
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              if (!isInitaoDocument) ...const [
                ButtonSegment(value: 'old', label: Text('OLD')),
                ButtonSegment(
                    value: 'without_table',
                    label: Text('WITHOUT TABLE', textAlign: TextAlign.center)),
              ],
              if (isInitaoDocument)
                const ButtonSegment(
                    value: 'initao_lgu',
                    label: Text('INITAO LGU', textAlign: TextAlign.center)),
            ],
            selected: {effectiveBidSecurityTemplate},
            onSelectionChanged: (selection) {
              if (!isInitaoDocument) _selectBidSecurity(selection);
            },
          ),
        ),
      ],
    );
  }
}
