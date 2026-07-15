import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_parse.dart';

/// A persisted low-stock/out-of-stock alert, written only by the
/// onProductStockChange Cloud Function trigger when a product's stock
/// crosses the low-stock threshold (Requirement in Detail §27.3 / §34.2).
class LowStockAlertModel {
  final String alertId;
  final String productId;
  final String shopId;
  final String productName;
  final double stock;
  final double threshold;
  final String alertType; // 'low_stock' | 'out_of_stock'
  final bool resolved;
  final DateTime createdAt;

  const LowStockAlertModel({
    required this.alertId,
    required this.productId,
    required this.shopId,
    required this.productName,
    required this.stock,
    required this.threshold,
    required this.alertType,
    required this.resolved,
    required this.createdAt,
  });

  bool get isOutOfStock => alertType == 'out_of_stock';

  factory LowStockAlertModel.fromMap(Map<String, dynamic> map) {
    return LowStockAlertModel(
      alertId: FirestoreParse.stringField(map['alertId']),
      productId: FirestoreParse.stringField(map['productId']),
      shopId: FirestoreParse.stringField(map['shopId']),
      productName: FirestoreParse.stringField(map['productName']),
      stock: FirestoreParse.doubleField(map['stock']),
      threshold: FirestoreParse.doubleField(map['threshold']),
      alertType: FirestoreParse.stringField(
        map['alertType'],
        fallback: 'low_stock',
      ),
      resolved: map['resolved'] == true,
      createdAt: FirestoreParse.dateTimeField(map['createdAt']),
    );
  }

  static LowStockAlertModel? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final alert = LowStockAlertModel.fromMap(map);
    if (alert.alertId.isEmpty && alert.productId.isEmpty) return null;
    return alert;
  }

  static LowStockAlertModel? tryFromQueryDocument(QueryDocumentSnapshot doc) {
    return FirestoreParse.tryParseQuery(
      doc,
      LowStockAlertModel.fromMap,
      validate: (a) => a.alertId.isNotEmpty || a.productId.isNotEmpty,
    );
  }
}
