part of '../../screens/pdf_editor_screen.dart';

extension _SidebarPanel on _PdfEditorScreenState {
  Widget buildSidebar(bool isWide) => Theme(
        data: _sidebarTheme(Theme.of(context)),
        child: Container(
          width: isWide ? 400 : double.infinity,
          color: const Color(0xFFF6F8F7),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: _sidebarBorder))),
              child: Row(children: [
                Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEEF7F2),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.tune_rounded,
                        size: 20, color: _sidebarGreen)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Document setup',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: _sidebarInk)),
                      SizedBox(height: 3),
                      Text('Prepare your bid documents',
                          style: TextStyle(fontSize: 12, color: _sidebarMuted)),
                    ])),
              ]),
            ),
            Expanded(
                child: ListView(
              controller: sidebarScrollController,
              // The footer is outside this viewport; only a breathing gap is needed.
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                documentTemplateFields(),
                const SizedBox(height: 16),
                _SidebarCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      sectionHeading(
                        Icons.business_center_outlined,
                        'PROJECT INFORMATION',
                        subtitle: 'Bid and procuring entity details',
                      ),
                      formField(
                        label: 'Province',
                        controller: provinceController,
                      ),
                      formField(
                        label: 'Municipality',
                        controller: municipalityController,
                      ),
                      formField(
                        label: 'Project Title',
                        controller: projectTitleController,
                        maxLines: 3,
                      ),
                      formField(
                        label: 'Reference Number',
                        controller: referenceNumberController,
                      ),
                      formField(
                        label: 'Procuring Entity',
                        controller: procuringEntityController,
                        maxLines: 2,
                      ),
                      formField(
                        label: 'Date',
                        controller: dateController,
                      ),
                      formField(
                        label: 'Bidder Name',
                        controller: bidderNameController,
                      ),
                      submittedByField(),
                    ])),
                const Padding(
                    padding: EdgeInsets.fromLTRB(4, 24, 4, 12),
                    child: Text('DOCUMENT COMPONENTS',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: _sidebarMuted))),
                bidSecuringDeclarationFields(),
                const SizedBox(height: 12),
                omnibusFields(),
                const SizedBox(height: 12),
                slccFields(),
                const SizedBox(height: 12),
                technicalSpecificationsFields(),
                const SizedBox(height: 12),
                priceScheduleFields(),
                const SizedBox(height: 12),
                scheduleRequirementsFields(),
                const SizedBox(height: 12),
                afterSalesServiceFields(),
                const SizedBox(height: 12),
                productWarrantyFields(),
                if (errorMessage != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(errorMessage!,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.red))),
              ],
            )),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: _sidebarBorder))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: isGenerating ? null : generatePdf,
                      icon: isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_outlined, size: 20),
                      label: Text(
                        isGenerating ? 'Generating...' : 'Generate PDF',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4F3A),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: isGenerating || isExportingWord
                          ? null
                          : exportEditableWord,
                      icon: isExportingWord
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.description_outlined, size: 20),
                      label: Text(
                        isExportingWord
                            ? 'Exporting Word...'
                            : 'Export Word (.docx)',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0B4F3A),
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: Color(0xFF0B4F3A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ]),
            ),
          ]),
        ),
      );
}
