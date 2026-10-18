import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_parse.dart';

/// Represents a wholesale volume price tier (e.g. 10kg+ @ ₹85/kg)
class PriceTier {
  final double minQuantity;
  final double unitPrice;

  const PriceTier({
    required this.minQuantity,
    required this.unitPrice,
  });

  Map<String, dynamic> toMap() => {
    'minQuantity': minQuantity,
    'unitPrice': unitPrice,
  };

  factory PriceTier.fromMap(Map<String, dynamic> map) => PriceTier(
    minQuantity: (map['minQuantity'] as num?)?.toDouble() ?? 0.0,
    unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0.0,
  );
}

class ProductModel {
  final String productId;
  final String shopId;
  final String name;
  final String categoryId; // link to categories collection
  final double price; // default retail price (> 0)
  final double costPrice; // wholesale purchase cost / COGS per unit
  final String
  measurementType; // kg, gm, piece, box — immutable after first sale
  final double stock; // must be >= 0
  final String status; // Canonical: Active, Inactive
  final String barcode; // optional barcode / UPC / EAN string
  final List<PriceTier> tierPricing; // optional bulk wholesale pricing tiers
  final DateTime createdAt; // immutable

  const ProductModel({
    required this.productId,
    required this.shopId,
    required this.name,
    this.barcode = '',
    this.categoryId = '',
    required this.price,
    this.costPrice = 0.0,
    required this.measurementType,
    required this.stock,
    required this.status,
    this.tierPricing = const [],
    required this.createdAt,
  });

  /// Returns the applicable unit price for a given volume quantity.
  /// If bulk wholesale tiers are configured, matches the highest tier where quantity >= minQuantity.
  double getPriceForQuantity(double quantity) {
    if (tierPricing.isEmpty) return price;
    var activePrice = price;
    final sorted = List<PriceTier>.from(tierPricing)
      ..sort((a, b) => a.minQuantity.compareTo(b.minQuantity));
    for (final tier in sorted) {
      if (quantity >= tier.minQuantity) {
        activePrice = tier.unitPrice;
      }
    }
    return activePrice;
  }

  /// Whether this product can be sold.
  /// Case-insensitive so this is correct regardless of construction path —
  /// `fromMap` already normalizes casing, but the plain constructor (e.g.
  /// via `copyWith`) does not, so this getter cannot assume canonical casing.
  bool get isActive => status.toLowerCase() == 'active';

  /// Whether this product is sold by weight (kg/gm)
  bool get isWeightBased => measurementType == 'kg' || measurementType == 'gm';

  /// Whether this product is available for sale (active + in stock)
  bool get isAvailable => isActive && stock > 0;

  /// Canonical product status: Active, Inactive (matches backend)
  static String _normalizeProductStatus(dynamic value) {
    final s = FirestoreParse.stringField(value, fallback: 'Active');
    if (s.isEmpty) return 'Active';
    final lower = s.toLowerCase().trim();
    if (lower == 'active') return 'Active';
    if (lower == 'inactive' || lower == 'disabled') return 'Inactive';
    return s;
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    final rawTiers = map['tierPricing'] as List<dynamic>? ?? [];
    return ProductModel(
      productId: FirestoreParse.stringField(map['productId']),
      shopId: FirestoreParse.stringField(map['shopId']),
      name: FirestoreParse.stringField(map['name']),
      barcode: FirestoreParse.stringField(map['barcode']),
      categoryId: FirestoreParse.stringField(map['categoryId']),
      price: FirestoreParse.doubleField(map['price']),
      costPrice: FirestoreParse.doubleField(map['costPrice']),
      measurementType:
          FirestoreParse.stringField(map['measurementType'], fallback: 'piece'),
      stock: FirestoreParse.doubleField(map['stock']),
      status: _normalizeProductStatus(map['status']),
      tierPricing: rawTiers
          .map((t) => PriceTier.fromMap(Map<String, dynamic>.from(t as Map)))
          .toList(),
      createdAt: FirestoreParse.dateTimeField(map['createdAt']),
    );
  }

  static ProductModel? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final product = ProductModel.fromMap(map);
    if (product.productId.isEmpty && product.shopId.isEmpty) return null;
    return product;
  }

  static ProductModel? tryFromDocument(DocumentSnapshot doc) {
    return FirestoreParse.tryParse(
      doc,
      ProductModel.fromMap,
      validate: (p) => p.productId.isNotEmpty || p.name.isNotEmpty,
    );
  }

  static ProductModel? tryFromQueryDocument(QueryDocumentSnapshot doc) {
    return FirestoreParse.tryParseQuery(
      doc,
      ProductModel.fromMap,
      validate: (p) => p.productId.isNotEmpty || p.name.isNotEmpty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'shopId': shopId,
      'name': name,
      'barcode': barcode,
      'categoryId': categoryId,
      'price': price,
      'costPrice': costPrice,
      'measurementType': measurementType,
      'stock': stock,
      'status': status,
      'tierPricing': tierPricing.map((t) => t.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  ProductModel copyWith({
    String? productId,
    String? shopId,
    String? name,
    String? barcode,
    String? categoryId,
    double? price,
    double? costPrice,
    String? measurementType,
    double? stock,
    String? status,
    List<PriceTier>? tierPricing,
    DateTime? createdAt,
  }) {
    return ProductModel(
      productId: productId ?? this.productId,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      categoryId: categoryId ?? this.categoryId,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      measurementType: measurementType ?? this.measurementType,
      stock: stock ?? this.stock,
      status: status ?? this.status,
      tierPricing: tierPricing ?? this.tierPricing,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
