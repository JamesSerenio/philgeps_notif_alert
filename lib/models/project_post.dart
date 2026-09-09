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
  final String status;

  ProjectPost({
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
  });

  factory ProjectPost.fromJson(Map<String, dynamic> json) {
    return ProjectPost(
      id: json['id']?.toString() ?? '',
      lgu: json['lgu']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      referenceNumber: json['reference_number']?.toString() ??
          json['referenceNumber']?.toString() ??
          '',
      procuringEntity: json['procuring_entity']?.toString() ??
          json['procuringEntity']?.toString() ??
          '',
      areaOfDelivery: json['area_of_delivery']?.toString() ??
          json['areaOfDelivery']?.toString() ??
          '',
      deliveryPeriod: json['delivery_period']?.toString() ??
          json['deliveryPeriod']?.toString() ??
          '',
      classification: json['classification']?.toString() ?? '',
      abc: (json['abc'] ?? 0).toDouble(),
      budgetType: json['budget_type']?.toString() ?? 'ABC',
      isBiddingDoc: json['is_bidding_doc'] == true,
      status: json['status']?.toString() ?? 'old',
      closingDate: json['closingDate']?.toString() ??
          json['closing_date']?.toString() ??
          '',
      postingDate: json['postingDate']?.toString() ??
          json['posting_date']?.toString() ??
          '',
      url: json['url']?.toString() ?? '',
    );
  }
}

enum DeadlineStatus { safe, near, urgent, closed, unknown }
