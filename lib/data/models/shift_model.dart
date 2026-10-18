import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a cash movement within an active cashier shift
/// (Cash In = add change float, Cash Out = vendor payout / safe drop)
class ShiftMovement {
  final String id;
  final String type; // 'cash_in' or 'cash_out'
  final double amount;
  final String reason;
  final DateTime timestamp;
  final String authorizedBy;

  const ShiftMovement({
    required this.id,
    required this.type,
    required this.amount,
    required this.reason,
    required this.timestamp,
    this.authorizedBy = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'amount': amount,
      'reason': reason,
      'timestamp': Timestamp.fromDate(timestamp),
      'authorizedBy': authorizedBy,
    };
  }

  factory ShiftMovement.fromMap(Map<String, dynamic> map) {
    return ShiftMovement(
      id: map['id'] as String? ?? '',
      type: map['type'] as String? ?? 'cash_in',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      reason: map['reason'] as String? ?? '',
      timestamp: map['timestamp'] is Timestamp
          ? (map['timestamp'] as Timestamp).toDate()
          : (map['timestamp'] != null
              ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
              : DateTime.now()),
      authorizedBy: map['authorizedBy'] as String? ?? '',
    );
  }
}

/// Represents a cashier POS shift document
class ShiftModel {
  final String shiftId;
  final String shopId;
  final String cashierId;
  final String cashierName;
  final double openingFloat;
  final String status; // 'open', 'closed'
  final DateTime openedAt;
  final DateTime? closedAt;
  final double cashSales;
  final double upiSales;
  final double cardSales;
  final int orderCount;
  final List<ShiftMovement> movements;
  final double? actualCashCounted; // Blind count entered at shift close
  final double? difference; // Counted - Expected (Positive = Overage, Negative = Shortage)
  final String terminalId; // register / terminal identifier
  final String notes;

  const ShiftModel({
    required this.shiftId,
    required this.shopId,
    required this.cashierId,
    required this.cashierName,
    required this.openingFloat,
    required this.status,
    required this.openedAt,
    this.closedAt,
    this.cashSales = 0.0,
    this.upiSales = 0.0,
    this.cardSales = 0.0,
    this.orderCount = 0,
    this.movements = const [],
    this.actualCashCounted,
    this.difference,
    this.terminalId = '',
    this.notes = '',
  });

  bool get isOpen => status.toLowerCase() == 'open';

  double get cashInTotal => movements
      .where((m) => m.type == 'cash_in')
      .fold(0.0, (acc, m) => acc + m.amount);

  double get cashOutTotal => movements
      .where((m) => m.type == 'cash_out')
      .fold(0.0, (acc, m) => acc + m.amount);

  double get expectedCash =>
      openingFloat + cashSales + cashInTotal - cashOutTotal;

  double get grossSales => cashSales + upiSales + cardSales;

  Map<String, dynamic> toMap() {
    return {
      'shiftId': shiftId,
      'shopId': shopId,
      'cashierId': cashierId,
      'cashierName': cashierName,
      'openingFloat': openingFloat,
      'status': status,
      'openedAt': Timestamp.fromDate(openedAt),
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'cashSales': cashSales,
      'upiSales': upiSales,
      'cardSales': cardSales,
      'orderCount': orderCount,
      'movements': movements.map((m) => m.toMap()).toList(),
      'actualCashCounted': actualCashCounted,
      'difference': difference,
      'terminalId': terminalId,
      'notes': notes,
    };
  }

  factory ShiftModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ShiftModel.fromMap(data, doc.id);
  }

  factory ShiftModel.fromMap(Map<String, dynamic> map, [String? fallbackId]) {
    final rawMovements = map['movements'] as List<dynamic>? ?? [];
    return ShiftModel(
      shiftId: (map['shiftId'] as String?) ?? fallbackId ?? '',
      shopId: (map['shopId'] as String?) ?? '',
      cashierId: (map['cashierId'] as String?) ?? '',
      cashierName: (map['cashierName'] as String?) ?? '',
      openingFloat: (map['openingFloat'] as num?)?.toDouble() ?? 0.0,
      status: (map['status'] as String?) ?? 'open',
      openedAt: map['openedAt'] is Timestamp
          ? (map['openedAt'] as Timestamp).toDate()
          : DateTime.now(),
      closedAt: map['closedAt'] is Timestamp
          ? (map['closedAt'] as Timestamp).toDate()
          : null,
      cashSales: (map['cashSales'] as num?)?.toDouble() ?? 0.0,
      upiSales: (map['upiSales'] as num?)?.toDouble() ?? 0.0,
      cardSales: (map['cardSales'] as num?)?.toDouble() ?? 0.0,
      orderCount: (map['orderCount'] as num?)?.toInt() ?? 0,
      movements: rawMovements
          .map((m) => ShiftMovement.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList(),
      actualCashCounted: (map['actualCashCounted'] as num?)?.toDouble(),
      difference: (map['difference'] as num?)?.toDouble(),
      terminalId: (map['terminalId'] as String?) ?? '',
      notes: (map['notes'] as String?) ?? '',
    );
  }
}
