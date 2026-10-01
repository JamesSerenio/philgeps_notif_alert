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
  final double abc;
  final String budgetType;
  final String closingDate;
  final String postingDate;
  final String url;

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
    this.isDone = false,
    this.doneAt,
  });

  factory ProjectPost.fromJson(
    Map<String, dynamic> json,
  ) {
    double parseAbc(dynamic value) {
      if (value == null) {
        return 0;
      }

      if (value is num) {
        return value.toDouble();
      }

      final cleaned = value
          .toString()
          .replaceAll(',', '')
          .replaceAll('₱', '')
          .trim();

      return double.tryParse(cleaned) ?? 0;
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

      lgu: json['lgu']?.toString() ?? '',

      title: json['title']?.toString() ?? '',

      referenceNumber:
          json['reference_number']?.toString() ??
          json['referenceNumber']?.toString() ??
          '',

      procuringEntity:
          json['procuring_entity']?.toString() ??
          json['procuringEntity']?.toString() ??
          '',

      areaOfDelivery:
          json['area_of_delivery']?.toString() ??
          json['areaOfDelivery']?.toString() ??
          '',

      deliveryPeriod:
          json['delivery_period']?.toString() ??
          json['deliveryPeriod']?.toString() ??
          '',

      classification:
          json['classification']?.toString() ?? '',

      abc: parseAbc(
        json['abc'],
      ),

      budgetType:
          json['budget_type']?.toString() ??
          json['budgetType']?.toString() ??
          'ABC',

      closingDate:
          json['closing_date']?.toString() ??
          json['closingDate']?.toString() ??
          '',

      postingDate:
          json['posting_date']?.toString() ??
          json['postingDate']?.toString() ??
          '',

      url:
          json['url']?.toString() ?? '',

      isBiddingDoc:
          json['is_bidding_doc'] == true,

      isDone:
          json['is_done'] == true,

      doneAt: parseDoneAt(
        json['done_at'],
      ),

      status:
          json['status']?.toString() ?? 'old',
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
      id: id ?? this.id,

      lgu: lgu ?? this.lgu,

      title: title ?? this.title,

      referenceNumber:
          referenceNumber ??
          this.referenceNumber,

      procuringEntity:
          procuringEntity ??
          this.procuringEntity,

      areaOfDelivery:
          areaOfDelivery ??
          this.areaOfDelivery,

      deliveryPeriod:
          deliveryPeriod ??
          this.deliveryPeriod,

      classification:
          classification ??
          this.classification,

      abc:
          abc ?? this.abc,

      budgetType:
          budgetType ??
          this.budgetType,

      closingDate:
          closingDate ??
          this.closingDate,

      postingDate:
          postingDate ??
          this.postingDate,

      url:
          url ?? this.url,

      isBiddingDoc:
          isBiddingDoc ??
          this.isBiddingDoc,

      isDone:
          isDone ??
          this.isDone,

      doneAt:
          clearDoneAt
              ? null
              : doneAt ?? this.doneAt,

      status:
          status ?? this.status,
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