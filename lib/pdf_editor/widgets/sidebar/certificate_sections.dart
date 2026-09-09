part of '../../screens/pdf_editor_screen.dart';

extension _CertificateSections on _PdfEditorScreenState {
  Widget afterSalesServiceFields() {
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
        Icons.handyman_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'AFTER-SALES SERVICE CERTIFICATE',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        isLoadingAfterSales
            ? 'Loading saved value...'
            : isSavingAfterSales
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        formField(
          label: 'Number of Years',
          controller: afterSalesYearsController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const Text(
          'Example: 3 becomes “three (3) years” in the PDF.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF68736D)),
        ),
      ],
    );
  }

  Widget productWarrantyFields() {
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
        Icons.verified_outlined,
        color: Color(0xFF0B5D3B),
      ),
      title: const Text(
        'CERTIFICATE OF PRODUCT WARRANTY',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        isLoadingAfterSales
            ? 'Loading saved value...'
            : isSavingAfterSales
                ? 'Saving...'
                : 'Saved automatically',
      ),
      children: [
        formField(
          label: 'Number of Years',
          controller: warrantyYearsController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const Text(
          'Example: 3 becomes “three (3) years” in the PDF.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF68736D)),
        ),
      ],
    );
  }
}
