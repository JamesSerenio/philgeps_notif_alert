part of '../../screens/pdf_editor_screen.dart';

extension _BidSecuritySection on _PdfEditorScreenState {
  Widget bidSecuringDeclarationFields() {
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
            segments: const [
              ButtonSegment(value: 'old', label: Text('OLD')),
              ButtonSegment(
                value: 'without_table',
                label: Text('WITHOUT TABLE', textAlign: TextAlign.center),
              ),
              ButtonSegment(
                value: 'initao_lgu',
                label: Text('INITAO LGU', textAlign: TextAlign.center),
              ),
            ],
            selected: {selectedBidSecurityTemplate},
            onSelectionChanged: _selectBidSecurity,
          ),
        ),
      ],
    );
  }
}
