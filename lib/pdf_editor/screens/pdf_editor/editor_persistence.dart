part of '../pdf_editor_screen.dart';

extension _EditorPersistence on _PdfEditorScreenState {
  Future<void> _loadPhilgepsDeliveryPeriod() async {
    final referenceNumber = widget.referenceNumber.trim();
    if (referenceNumber.isEmpty) return;
    try {
      final row = await SupabaseConfig.client
          .from('philgeps_posts')
          .select('delivery_period')
          .eq('reference_number', referenceNumber)
          .maybeSingle();
      final deliveryPeriod = (row?['delivery_period'] ?? '').toString().trim();
      if (deliveryPeriod.isNotEmpty) {
        if (!mounted) return;
        _updateState(
            () => deliveredWeeksMonthsController.text = deliveryPeriod);
      } else {
        await _refreshPhilgepsDeliveryPeriod(referenceNumber);
      }
    } catch (error) {
      debugPrint('PhilGEPS delivery period load error: $error');
      await _refreshPhilgepsDeliveryPeriod(referenceNumber);
    } finally {
      await _loadManualDeliveryOverride(referenceNumber);
    }
  }

  Future<void> _loadManualDeliveryOverride(String referenceNumber) async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_schedule_requirements')
          // Keep this compatible with deployments created before the optional
          // is_manual_override migration was applied.
          .select('delivery_weeks_months')
          .eq('reference_number', referenceNumber)
          .maybeSingle();
      final saved = (row?['delivery_weeks_months'] ?? '').toString().trim();
      if (mounted && saved.isNotEmpty) {
        _updateState(() => deliveredWeeksMonthsController.text = saved);
      }
    } catch (error) {
      debugPrint('Delivery Period override load error: $error');
    } finally {
      isLoadingScheduleRequirements = false;
      if (mounted) _updateState(() {});
    }
  }

  void _scheduleRequirementsSave() {
    if (isLoadingScheduleRequirements) return;
    _invalidateGeneratedPdf();
    hasPendingDeliveryPeriodOverride = true;
    scheduleRequirementsSaveTimer?.cancel();
    scheduleRequirementsSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _saveScheduleRequirements,
    );
  }

  Future<void> _saveScheduleRequirements() async {
    final referenceNumber = widget.referenceNumber.trim();
    if (referenceNumber.isEmpty) return;
    if (mounted) _updateState(() => isSavingScheduleRequirements = true);
    try {
      await SupabaseConfig.client.from('bid_schedule_requirements').upsert(
        {
          'reference_number': referenceNumber,
          'delivery_weeks_months': deliveredWeeksMonthsController.text.trim(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
      hasPendingDeliveryPeriodOverride = false;
    } catch (error) {
      debugPrint('Delivery Period override save error: $error');
    } finally {
      if (mounted) _updateState(() => isSavingScheduleRequirements = false);
    }
  }

  Future<void> _refreshPhilgepsDeliveryPeriod(String referenceNumber) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              'https://philgepsnotifalert-production.up.railway.app/'
              'refresh-delivery-period',
            ),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'referenceNumber': referenceNumber}),
          )
          .timeout(const Duration(minutes: 2));
      if (response.statusCode != 200) {
        debugPrint('Delivery Period refresh failed: ${response.body}');
        return;
      }
      final decoded = jsonDecode(response.body);
      final deliveryPeriod = decoded is Map
          ? (decoded['deliveryPeriod'] ?? '').toString().trim()
          : '';
      if (!mounted || deliveryPeriod.isEmpty) return;
      _updateState(() => deliveredWeeksMonthsController.text = deliveryPeriod);
    } catch (error) {
      debugPrint('Delivery Period refresh request error: $error');
    }
  }

  Future<void> _loadAfterSalesSettings() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_after_sales_settings')
          .select('service_years, warranty_years')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      afterSalesYearsController.text = (row?['service_years'] ?? 1).toString();
      warrantyYearsController.text = (row?['warranty_years'] ?? 2).toString();
    } catch (error) {
      debugPrint('After-sales settings load error: $error');
    } finally {
      if (mounted) _updateState(() => isLoadingAfterSales = false);
    }
  }

  void _scheduleAfterSalesSave() {
    if (isLoadingAfterSales) return;
    _invalidateGeneratedPdf();
    afterSalesSaveTimer?.cancel();
    afterSalesSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _saveAfterSalesSettings,
    );
  }

  Future<void> _saveAfterSalesSettings() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    final years = int.tryParse(afterSalesYearsController.text.trim());
    final warrantyYears = int.tryParse(warrantyYearsController.text.trim());
    if (years == null ||
        years < 1 ||
        warrantyYears == null ||
        warrantyYears < 1) {
      return;
    }
    if (mounted) _updateState(() => isSavingAfterSales = true);
    try {
      await SupabaseConfig.client.from('bid_after_sales_settings').upsert(
        {
          'reference_number': widget.referenceNumber.trim(),
          'service_years': years,
          'warranty_years': warrantyYears,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
    } catch (error) {
      debugPrint('After-sales settings save error: $error');
    } finally {
      if (mounted) _updateState(() => isSavingAfterSales = false);
    }
  }

  Future<void> _loadUnitSuggestions() async {
    try {
      final rows = await SupabaseConfig.client
          .from('technical_specification_units')
          .select('code')
          .order('sort_order');
      final loaded = rows
          .map((row) => (row['code'] ?? '').toString().trim())
          .where((unit) => unit.isNotEmpty)
          .toList();
      if (loaded.isNotEmpty && mounted) {
        _updateState(() => unitSuggestions = loaded);
      }
    } catch (error) {
      debugPrint('Unit suggestions load error: $error');
    }
  }

  Future<void> _loadTechnicalSpecifications() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_technical_specifications')
          .select('specifications')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      final savedSpecifications = row?['specifications'];
      if (savedSpecifications is List) {
        for (final value in savedSpecifications.take(72)) {
          if (value is Map) {
            _addTechnicalSpecification(
              specification: (value['specification'] ?? '').toString(),
              quantity: (value['quantity'] ?? '').toString().trim().isEmpty
                  ? '1'
                  : value['quantity'].toString(),
              unit: (value['unit'] ?? '').toString().trim().isEmpty
                  ? 'unit'
                  : value['unit'].toString(),
              parameter: (value['parameter'] ?? '').toString(),
              rebuild: false,
            );
          }
        }
      }
    } catch (error) {
      debugPrint('Technical specifications load error: $error');
    } finally {
      if (mounted) {
        _updateState(() => isLoadingTechnicalSpecifications = false);
      }
      await _loadPriceSchedule();
    }
  }

  Future<void> _loadPriceSchedule() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_price_schedules')
          .select('total_prices_per_unit')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      final savedPrices = row?['total_prices_per_unit'];
      if (savedPrices is List) {
        for (var index = 0;
            index < savedPrices.length && index < priceScheduleEntries.length;
            index++) {
          final value = savedPrices[index];
          final savedValue = value is Map
              ? (value['totalPricePerUnit'] ?? '').toString()
              : value.toString();
          priceScheduleEntries[index].totalPricePerUnit.text =
              const _ThousandsSeparatorInputFormatter()
                  .formatEditUpdate(
                    const TextEditingValue(),
                    TextEditingValue(text: savedValue),
                  )
                  .text;
          final deduction =
              value is Map ? (value['deduction'] ?? '').toString() : '';
          priceScheduleEntries[index].deduction.text =
              const _ThousandsSeparatorInputFormatter()
                  .formatEditUpdate(
                    const TextEditingValue(),
                    TextEditingValue(text: deduction),
                  )
                  .text;
        }
      }
    } catch (error) {
      debugPrint('Price schedule load error: $error');
    } finally {
      if (mounted) _updateState(() => isLoadingPriceSchedule = false);
    }
  }

  void _schedulePriceScheduleSave() {
    if (isLoadingPriceSchedule) return;
    _invalidateGeneratedPdf();
    priceScheduleSaveTimer?.cancel();
    priceScheduleSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _savePriceSchedule,
    );
    if (mounted) _updateState(() {});
  }

  Future<void> _savePriceSchedule() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    if (mounted) _updateState(() => isSavingPriceSchedule = true);
    try {
      await SupabaseConfig.client.from('bid_price_schedules').upsert(
        {
          'reference_number': widget.referenceNumber.trim(),
          'total_prices_per_unit': [
            for (final entry in priceScheduleEntries)
              {
                'totalPricePerUnit': entry.totalPricePerUnit.text.trim(),
                'deduction': entry.deduction.text.trim(),
              },
          ],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
    } catch (error) {
      debugPrint('Price schedule save error: $error');
    } finally {
      if (mounted) _updateState(() => isSavingPriceSchedule = false);
    }
  }

  void _scheduleTechnicalSpecificationsSave() {
    if (isLoadingTechnicalSpecifications) return;
    _invalidateGeneratedPdf();
    technicalSpecificationsSaveTimer?.cancel();
    technicalSpecificationsSaveTimer = Timer(
      const Duration(milliseconds: 700),
      _saveTechnicalSpecifications,
    );
    if (mounted) _updateState(() {});
  }

  Future<void> _saveTechnicalSpecifications() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    if (mounted) _updateState(() => isSavingTechnicalSpecifications = true);
    try {
      final specifications = [
        for (final entry in technicalSpecifications)
          {
            'specification': entry.specification.text.trim(),
            'quantity': entry.quantity.text.trim(),
            'unit': entry.unit.text.trim(),
            'parameter': entry.parameter.text.trim(),
          },
      ];
      await SupabaseConfig.client.from('bid_technical_specifications').upsert(
        {
          'reference_number': widget.referenceNumber.trim(),
          'specifications': specifications,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'reference_number',
      );
    } catch (error) {
      debugPrint('Technical specifications save error: $error');
    } finally {
      if (mounted) _updateState(() => isSavingTechnicalSpecifications = false);
    }
  }

  String get _omnibusPreferenceKey =>
      'bid_omnibus_template_${widget.referenceNumber.trim()}';

  Future<void> _loadOmnibus() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_omnibusPreferenceKey);
      if (!mounted || omnibusSelectionRevision != 0) return;
      _updateState(() => selectedOmnibusTemplate =
          saved == 'initao_lgu' ? 'initao_lgu' : 'old');
    } catch (error) {
      if (mounted)
        _updateState(() => omnibusSaveError = 'Could not load saved option');
    } finally {
      if (mounted) _updateState(() => isLoadingOmnibus = false);
    }
  }

  void _selectOmnibus(Set<String> selection) {
    final selectedTemplate = selection.first;
    final revision = ++omnibusSelectionRevision;
    _updateState(() {
      selectedOmnibusTemplate = selectedTemplate;
      isSavingOmnibus = true;
      omnibusSaveError = null;
    });
    _invalidateGeneratedPdf();
    // Serialize writes without blocking taps; only the latest save owns status.
    omnibusSave = omnibusSave.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        if (!await preferences.setString(
            _omnibusPreferenceKey, selectedTemplate)) {
          throw StateError('Omnibus preference was not saved');
        }
      } catch (error) {
        if (mounted && revision == omnibusSelectionRevision) {
          _updateState(() => omnibusSaveError = 'Could not save option');
        }
      } finally {
        if (mounted && revision == omnibusSelectionRevision) {
          _updateState(() => isSavingOmnibus = false);
        }
      }
    });
  }

  String get _bidSecurityPreferenceKey =>
      'bid_security_template_${widget.referenceNumber.trim()}';

  Future<void> _loadBidSecurity() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_bidSecurityPreferenceKey);
      if (!mounted || bidSecuritySelectionRevision != 0) return;
      _updateState(() => selectedBidSecurityTemplate =
          saved == 'without_table' || saved == 'initao_lgu' ? saved! : 'old');
    } catch (error) {
      if (mounted && bidSecuritySelectionRevision == 0) {
        _updateState(
            () => bidSecuritySaveError = 'Could not load saved option');
      }
    } finally {
      if (mounted) _updateState(() => isLoadingBidSecurity = false);
    }
  }

  void _selectBidSecurity(Set<String> selection) {
    final selectedTemplate = selection.first;
    final revision = ++bidSecuritySelectionRevision;
    _updateState(() {
      selectedBidSecurityTemplate = selectedTemplate;
      isSavingBidSecurity = true;
      bidSecuritySaveError = null;
    });
    _invalidateGeneratedPdf();
    // Save in tap order without disabling the selector or generating a PDF.
    bidSecuritySave = bidSecuritySave.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        if (!await preferences.setString(
            _bidSecurityPreferenceKey, selectedTemplate)) {
          throw StateError('Bid security preference was not saved');
        }
      } catch (error) {
        if (mounted && revision == bidSecuritySelectionRevision) {
          _updateState(() => bidSecuritySaveError = 'Could not save option');
        }
      } finally {
        if (mounted && revision == bidSecuritySelectionRevision) {
          _updateState(() => isSavingBidSecurity = false);
        }
      }
    });
  }

  Future<void> _loadSlcc() async {
    try {
      final row = await SupabaseConfig.client
          .from('bid_slcc_entries')
          .select('template_type')
          .eq('reference_number', widget.referenceNumber.trim())
          .maybeSingle();
      if (row != null) {
        final savedTemplate = (row['template_type'] ?? '').toString();
        if (savedTemplate == 'none' ||
            savedTemplate == 'cctv' ||
            savedTemplate == 'streetlight') {
          selectedSlccTemplate = savedTemplate;
        }
      }
    } catch (error) {
      debugPrint('SLCC load error: $error');
    } finally {
      if (mounted) _updateState(() => isLoadingSlcc = false);
    }
  }

  void _scheduleSlccSave() {
    if (isLoadingSlcc) return;
    slccSaveTimer?.cancel();
    slccSaveTimer = Timer(const Duration(milliseconds: 700), _saveSlcc);
  }

  Future<void> _saveSlcc() async {
    if (widget.referenceNumber.trim().isEmpty) return;
    if (mounted) _updateState(() => isSavingSlcc = true);
    try {
      final data = <String, dynamic>{
        'reference_number': widget.referenceNumber.trim(),
        'template_type': selectedSlccTemplate,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      await SupabaseConfig.client.from('bid_slcc_entries').upsert(
            data,
            onConflict: 'reference_number',
          );
    } catch (error) {
      debugPrint('SLCC save error: $error');
    } finally {
      if (mounted) _updateState(() => isSavingSlcc = false);
    }
  }
}
