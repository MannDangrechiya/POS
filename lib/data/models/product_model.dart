import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_parse.dart';

class ProductModel {
  final String productId;
  final String shopId;
  final String name;
  final String categoryId; // link to categories collection
  final double price; // must be > 0
  final String
  measurementType; // kg, gm, piece, box — immutable after first sale
  final double stock; // must be >= 0
  final String status; // Canonical: Active, Inactive
  final DateTime createdAt; // immutable

  const ProductModel({
    required this.productId,
    required this.shopId,
    required this.name,
    this.categoryId = '',
    required this.price,
    required this.measurementType,
    required this.stock,
    required this.status,
    required this.createdAt,
  });

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
    return ProductModel(
      productId: FirestoreParse.stringField(map['productId']),
      shopId: FirestoreParse.stringField(map['shopId']),
      name: FirestoreParse.stringField(map['name']),
      categoryId: FirestoreParse.stringField(map['categoryId']),
      price: FirestoreParse.doubleField(map['price']),
      measurementType:
          FirestoreParse.stringField(map['measurementType'], fallback: 'piece'),
      stock: FirestoreParse.doubleField(map['stock']),
      status: _normalizeProductStatus(map['status']),
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
      'categoryId': categoryId,
      'price': price,
      'measurementType': measurementType,
      'stock': stock,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  ProductModel copyWith({
    String? productId,
    String? shopId,
    String? name,
    String? categoryId,
    double? price,
    String? measurementType,
    double? stock,
    String? status,
    DateTime? createdAt,
  }) {
    return ProductModel(
      productId: productId ?? this.productId,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      price: price ?? this.price,
      measurementType: measurementType ?? this.measurementType,
      stock: stock ?? this.stock,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
