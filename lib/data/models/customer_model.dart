import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_parse.dart';

class CustomerModel {
  final String customerId;
  final String shopId;
  final String name;
  final String mobile;
  final double creditLimit;
  final double currentBalance;
  final DateTime createdAt; // immutable

  const CustomerModel({
    required this.customerId,
    required this.shopId,
    required this.name,
    required this.mobile,
    this.creditLimit = 10000.0,
    this.currentBalance = 0.0,
    required this.createdAt,
  });

  factory CustomerModel.fromMap(Map<String, dynamic> map) {
    return CustomerModel(
      customerId: FirestoreParse.stringField(map['customerId']),
      shopId: FirestoreParse.stringField(map['shopId']),
      name: FirestoreParse.stringField(map['name']),
      mobile: FirestoreParse.stringField(map['mobile']),
      creditLimit: FirestoreParse.doubleField(map['creditLimit'], fallback: 10000.0),
      currentBalance: FirestoreParse.doubleField(map['currentBalance'], fallback: 0.0),
      createdAt: FirestoreParse.dateTimeField(map['createdAt']),
    );
  }

  static CustomerModel? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final customer = CustomerModel.fromMap(map);
    if (customer.customerId.isEmpty) return null;
    return customer;
  }

  static CustomerModel? tryFromQueryDocument(QueryDocumentSnapshot doc) {
    return FirestoreParse.tryParseQuery(
      doc,
      CustomerModel.fromMap,
      validate: (c) => c.customerId.isNotEmpty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'shopId': shopId,
      'name': name,
      'mobile': mobile,
      'creditLimit': creditLimit,
      'currentBalance': currentBalance,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  CustomerModel copyWith({
    String? customerId,
    String? shopId,
    String? name,
    String? mobile,
    double? creditLimit,
    double? currentBalance,
    DateTime? createdAt,
  }) {
    return CustomerModel(
      customerId: customerId ?? this.customerId,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      mobile: mobile ?? this.mobile,
      creditLimit: creditLimit ?? this.creditLimit,
      currentBalance: currentBalance ?? this.currentBalance,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
