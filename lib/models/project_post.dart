part of '../main.dart';

class ProjectPost {
  final String id;
  final String lgu;
  final String title;
  final String referenceNumber;
  final String procuringEntity;
  final String areaOfDelivery;
  final String deliveryPeriod;
  final String classification;
  final double? abc;
  final String budgetType;
  final String closingDate;
  final String postingDate;
  final DateTime? discoveredAt;
  final String url;
  final String source;
  final String officialNoticeId;
  final String procurementMode;
  final String documentStatus;
  final String documentUrl;
  String get displayTitle => title.trim().isEmpty ? 'Untitled Project' : title;
  bool get isModern => source == 'modern';
  String get sourceLabel => isModern ? 'philgeps.gov.ph' : 'PhilGEPS';
  String get sourceUrl => isModern ? url : 'https://notices.philgeps.gov.ph/';
  String get documentLabel => switch (documentStatus) {
        'preview' => 'Open BDocs',
        'download' => 'Download BDocs',
        'access_required' => 'Login / Access Required',
        _ => 'BDocs Not Verified',
      };

  final bool isBiddingDoc;

  // DONE WORKFLOW
  final bool isDone;
  final DateTime? doneAt;

  final String status;

  const ProjectPost({
    required this.id,
    required this.lgu,
    required this.title,
    required this.closingDate,
    required this.postingDate,
    required this.url,
    required this.referenceNumber,
    required this.procuringEntity,
    required this.areaOfDelivery,
    required this.deliveryPeriod,
    required this.classification,
    required this.abc,
    required this.budgetType,
    required this.isBiddingDoc,
    required this.status,

    // Hindi required para compatible sa existing code
    this.discoveredAt,
    this.isDone = false,
    this.doneAt,
    this.source = 'existing',
    this.officialNoticeId = '',
    this.procurementMode = '',
    this.documentStatus = 'unverified',
    this.documentUrl = '',
  });

  factory ProjectPost.fromJson(
    Map<String, dynamic> json,
  ) {
    String firstText(List<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    double? parseAbc(dynamic value) {
      if (value == null) {
        return null;
      }

      if (value is num) {
        return value.toDouble();
      }

      final cleaned =
          value.toString().replaceAll(',', '').replaceAll('₱', '').trim();

      return double.tryParse(cleaned);
    }

    DateTime? parseDoneAt(dynamic value) {
      if (value == null) {
        return null;
      }

      final text = value.toString().trim();

      if (text.isEmpty) {
        return null;
      }

      return DateTime.tryParse(text);
    }

    return ProjectPost(
      id: json['id']?.toString() ?? '',
      source: json['source']?.toString() ?? 'existing',
      officialNoticeId: json['official_notice_id']?.toString() ?? '',
      procurementMode: json['procurement_mode']?.toString() ?? '',
      documentStatus: json['document_status']?.toString() ?? 'unverified',
      documentUrl: json['document_url']?.toString() ?? '',
      lgu: firstText(['lgu', 'municipality']),
      title: firstText(['title', 'project_title', 'projectTitle']),
      referenceNumber:
          firstText(['reference_number', 'referenceNumber', 'reference_no']),
      procuringEntity:
          firstText(['procuring_entity', 'procuringEntity', 'entity']),
      areaOfDelivery: firstText(
          ['area_of_delivery', 'areaOfDelivery', 'province', 'location']),
      deliveryPeriod: json['delivery_period']?.toString() ??
          json['deliveryPeriod']?.toString() ??
          '',
      classification: json['classification']?.toString() ?? '',
      abc: parseAbc(
        json['abc'],
      ),
      budgetType: json['budget_type']?.toString() ??
          json['budgetType']?.toString() ??
          'ABC',
      closingDate: firstText(
          ['manual_deadline', 'manualDeadline', 'closing_date', 'closingDate']),
      postingDate: json['posting_date']?.toString() ??
          json['postingDate']?.toString() ??
          '',
      url: (json['official_url'] ?? json['url'])?.toString() ?? '',
      isBiddingDoc: json['is_bidding_doc'] == true,
      isDone: json['is_done'] == true,
      doneAt: parseDoneAt(
        json['done_at'],
      ),
      discoveredAt: parsePhilgepsDate(
          (json['first_seen_at'] ?? json['created_at'])?.toString()),
      status: json['status']?.toString() ?? 'old',
    );
  }

  ProjectPost copyWith({
    String? id,
    String? lgu,
    String? title,
    String? referenceNumber,
    String? procuringEntity,
    String? areaOfDelivery,
    String? deliveryPeriod,
    String? classification,
    double? abc,
    String? budgetType,
    String? closingDate,
    String? postingDate,
    String? url,
    bool? isBiddingDoc,
    bool? isDone,
    DateTime? doneAt,
    bool clearDoneAt = false,
    String? status,
  }) {
    return ProjectPost(
      discoveredAt: discoveredAt,
      source: source,
      officialNoticeId: officialNoticeId,
      procurementMode: procurementMode,
      documentStatus: documentStatus,
      documentUrl: documentUrl,
      id: id ?? this.id,
      lgu: lgu ?? this.lgu,
      title: title ?? this.title,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      procuringEntity: procuringEntity ?? this.procuringEntity,
      areaOfDelivery: areaOfDelivery ?? this.areaOfDelivery,
      deliveryPeriod: deliveryPeriod ?? this.deliveryPeriod,
      classification: classification ?? this.classification,
      abc: abc ?? this.abc,
      budgetType: budgetType ?? this.budgetType,
      closingDate: closingDate ?? this.closingDate,
      postingDate: postingDate ?? this.postingDate,
      url: url ?? this.url,
      isBiddingDoc: isBiddingDoc ?? this.isBiddingDoc,
      isDone: isDone ?? this.isDone,
      doneAt: clearDoneAt ? null : doneAt ?? this.doneAt,
      status: status ?? this.status,
    );
  }
}

enum DeadlineStatus {
  safe,
  near,
  urgent,
  closed,
  unknown,
}
