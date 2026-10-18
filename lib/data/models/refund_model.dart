import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single returned item within a refund transaction
class RefundItem {
  final String productId;
  final String productName;
  final double quantityReturned;
  final double unitPrice;
  final double refundAmount;
  final String disposition; // 'restock' or 'damaged'
  final String reason;

  const RefundItem({
    required this.productId,
    required this.productName,
    required this.quantityReturned,
    required this.unitPrice,
    required this.refundAmount,
    this.disposition = 'restock',
    this.reason = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'quantityReturned': quantityReturned,
      'unitPrice': unitPrice,
      'refundAmount': refundAmount,
      'disposition': disposition,
      'reason': reason,
    };
  }

  factory RefundItem.fromMap(Map<String, dynamic> map) {
    return RefundItem(
      productId: map['productId'] as String? ?? '',
      productName: map['productName'] as String? ?? '',
      quantityReturned: (map['quantityReturned'] as num?)?.toDouble() ?? 0.0,
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0.0,
      refundAmount: (map['refundAmount'] as num?)?.toDouble() ?? 0.0,
      disposition: map['disposition'] as String? ?? 'restock',
      reason: map['reason'] as String? ?? '',
    );
  }
}

/// Represents an itemized customer return & refund transaction document
class RefundModel {
  final String refundId;
  final String shopId;
  final String orderId;
  final String customerId;
  final String customerName;
  final String employeeId;
  final String employeeName;
  final String shiftId;
  final String terminalId; // register / terminal identifier
  final List<RefundItem> items;
  final double totalRefundAmount;
  final String refundMethod; // 'cash', 'original', 'store_credit'
  final String reason;
  final DateTime createdAt;

  const RefundModel({
    required this.refundId,
    required this.shopId,
    required this.orderId,
    this.customerId = '',
    this.customerName = '',
    required this.employeeId,
    this.employeeName = '',
    this.shiftId = '',
    this.terminalId = '',
    required this.items,
    required this.totalRefundAmount,
    required this.refundMethod,
    this.reason = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'refundId': refundId,
      'shopId': shopId,
      'orderId': orderId,
      'customerId': customerId,
      'customerName': customerName,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'shiftId': shiftId,
      'terminalId': terminalId,
      'items': items.map((i) => i.toMap()).toList(),
      'totalRefundAmount': totalRefundAmount,
      'refundMethod': refundMethod,
      'reason': reason,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory RefundModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return RefundModel.fromMap(doc.data() ?? {}, doc.id);
  }

  factory RefundModel.fromMap(Map<String, dynamic> map, [String? fallbackId]) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    return RefundModel(
      refundId: (map['refundId'] as String?) ?? fallbackId ?? '',
      shopId: (map['shopId'] as String?) ?? '',
      orderId: (map['orderId'] as String?) ?? '',
      customerId: (map['customerId'] as String?) ?? '',
      customerName: (map['customerName'] as String?) ?? '',
      employeeId: (map['employeeId'] as String?) ?? '',
      employeeName: (map['employeeName'] as String?) ?? '',
      shiftId: (map['shiftId'] as String?) ?? '',
      terminalId: (map['terminalId'] as String?) ?? '',
      items: rawItems
          .map((i) => RefundItem.fromMap(Map<String, dynamic>.from(i as Map)))
          .toList(),
      totalRefundAmount: (map['totalRefundAmount'] as num?)?.toDouble() ?? 0.0,
      refundMethod: (map['refundMethod'] as String?) ?? 'cash',
      reason: (map['reason'] as String?) ?? '',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : (map['createdAt'] != null
              ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
              : DateTime.now()),
    );
  }
}
