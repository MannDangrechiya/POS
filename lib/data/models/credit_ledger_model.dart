import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_parse.dart';

/// Credit Ledger entry representing debit (purchase on credit)
/// or credit (settlement/payment) for customer Khata / Udhar tracking.
class CreditLedgerModel {
  final String ledgerId;
  final String customerId;
  final String shopId;
  final String? orderId;
  final String type; // 'debit' (owes more) or 'credit' (paid)
  final double amount;
  final double balanceAfter;
  final String description;
  final String? paymentMethod; // e.g. 'cash', 'upi', 'card' for settlements
  final String createdBy;
  final DateTime createdAt;

  const CreditLedgerModel({
    required this.ledgerId,
    required this.customerId,
    required this.shopId,
    this.orderId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    this.paymentMethod,
    required this.createdBy,
    required this.createdAt,
  });

  bool get isDebit => type.toLowerCase() == 'debit';
  bool get isCredit => type.toLowerCase() == 'credit';

  factory CreditLedgerModel.fromMap(Map<String, dynamic> map) {
    return CreditLedgerModel(
      ledgerId: FirestoreParse.stringField(map['ledgerId']),
      customerId: FirestoreParse.stringField(map['customerId']),
      shopId: FirestoreParse.stringField(map['shopId']),
      orderId: map['orderId'] != null ? FirestoreParse.stringField(map['orderId']) : null,
      type: FirestoreParse.stringField(map['type'], fallback: 'debit'),
      amount: FirestoreParse.doubleField(map['amount']),
      balanceAfter: FirestoreParse.doubleField(map['balanceAfter']),
      description: FirestoreParse.stringField(map['description']),
      paymentMethod: map['paymentMethod'] != null ? FirestoreParse.stringField(map['paymentMethod']) : null,
      createdBy: FirestoreParse.stringField(map['createdBy']),
      createdAt: FirestoreParse.dateTimeField(map['createdAt']),
    );
  }

  static CreditLedgerModel? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final model = CreditLedgerModel.fromMap(map);
    if (model.ledgerId.isEmpty) return null;
    return model;
  }

  static CreditLedgerModel? tryFromQueryDocument(QueryDocumentSnapshot doc) {
    return FirestoreParse.tryParseQuery(
      doc,
      CreditLedgerModel.fromMap,
      validate: (m) => m.ledgerId.isNotEmpty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ledgerId': ledgerId,
      'customerId': customerId,
      'shopId': shopId,
      if (orderId != null) 'orderId': orderId,
      'type': type,
      'amount': amount,
      'balanceAfter': balanceAfter,
      'description': description,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
