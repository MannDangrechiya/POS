import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_parse.dart';

class OrderModel {
  final String orderId; // immutable
  final String shopId;
  final String customerId;
  final String customerName; // snapshot for display
  final String employeeId; // immutable
  final String employeeName; // snapshot for display
  final double totalAmount; // calculated
  final String paymentMethod; // Cash, UPI, Card
  final String paymentStatus; // Success
  final String orderStatus; // pending, locked, cancelled (canonical)
  final String terminalId; // register / terminal identifier
  final DateTime createdAt; // immutable

  const OrderModel({
    required this.orderId,
    required this.shopId,
    required this.customerId,
    this.customerName = '',
    required this.employeeId,
    this.employeeName = '',
    required this.totalAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.orderStatus,
    this.terminalId = '',
    required this.createdAt,
  });

  /// Whether this order is completed and locked
  bool get isCompleted => orderStatus.toLowerCase() == 'locked';

  /// Whether this order was cancelled
  bool get isCancelled => orderStatus.toLowerCase() == 'cancelled';

  /// Whether this order is still pending (can be cancelled)
  bool get isPending => orderStatus.toLowerCase() == 'pending';

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      orderId: FirestoreParse.stringField(map['orderId']),
      shopId: FirestoreParse.stringField(map['shopId']),
      customerId: FirestoreParse.stringField(map['customerId']),
      customerName: FirestoreParse.stringField(map['customerName']),
      employeeId: FirestoreParse.stringField(map['employeeId']),
      employeeName: FirestoreParse.stringField(map['employeeName']),
      totalAmount: FirestoreParse.doubleField(map['totalAmount']),
      paymentMethod: FirestoreParse.stringField(map['paymentMethod']),
      paymentStatus: FirestoreParse.stringField(map['paymentStatus']),
      orderStatus: FirestoreParse.stringField(map['orderStatus']),
      terminalId: FirestoreParse.stringField(map['terminalId']),
      createdAt: FirestoreParse.dateTimeField(map['createdAt']),
    );
  }

  static OrderModel? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final order = OrderModel.fromMap(map);
    if (order.orderId.isEmpty) return null;
    return order;
  }

  static OrderModel? tryFromQueryDocument(QueryDocumentSnapshot doc) {
    return FirestoreParse.tryParseQuery(
      doc,
      OrderModel.fromMap,
      validate: (o) => o.orderId.isNotEmpty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'shopId': shopId,
      'customerId': customerId,
      'customerName': customerName,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'totalAmount': totalAmount,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'orderStatus': orderStatus,
      'terminalId': terminalId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
