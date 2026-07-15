import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_parse.dart';

class UserModel {
  final String userId;
  final String name;
  final String email;
  final String phone;
  final String role; // immutable: super_admin, admin, employee, viewer
  final String shopId;
  final String status; // Active, Inactive, Suspended
  final DateTime createdAt; // immutable

  const UserModel({
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.shopId,
    required this.status,
    required this.createdAt,
  });

  /// Whether this user is allowed to log in (canonical status 'Active')
  bool get isActive => status == 'Active';

  /// Whether this user is suspended
  bool get isSuspended => status == 'Suspended';

  /// Whether this user has been soft-deleted (Super Admin only — see
  /// deleteEmployee.ts). The Firestore document is kept so historical
  /// orders/audit logs can still resolve the userId; login is blocked the
  /// same as any other non-Active status.
  bool get isDeleted => status == 'Deleted';

  /// Normalize role to canonical: SuperAdmin, Admin, Employee, Viewer (matches Firestore/backend)
  static String _normalizeRole(String value) {
    if (value.isEmpty) return '';
    final lower = value.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '');
    if (lower == 'superadmin') return 'SuperAdmin';
    if (lower == 'admin') return 'Admin';
    if (lower == 'employee') return 'Employee';
    if (lower == 'viewer') return 'Viewer';
    return value;
  }

  /// Normalize status to canonical: Active, Inactive, Suspended
  /// Accepts string, bool, or int from Firestore for backward compatibility.
  static String _normalizeStatus(dynamic value) {
    if (value == null) return 'Inactive';
    if (value is bool) return value ? 'Active' : 'Inactive';
    if (value is int) return value != 0 ? 'Active' : 'Inactive';
    final s = value is String ? value : value.toString();
    if (s.isEmpty) return 'Inactive';
    final lower = s.toLowerCase().trim();
    if (lower == 'active') return 'Active';
    if (lower == 'inactive') return 'Inactive';
    if (lower == 'suspended') return 'Suspended';
    if (lower == 'deleted') return 'Deleted';
    return 'Inactive'; // unknown value -> deny by default
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      userId: FirestoreParse.stringField(map['userId']),
      name: FirestoreParse.stringField(map['name']),
      email: FirestoreParse.stringField(map['email']),
      phone: FirestoreParse.stringField(map['phone']),
      role: _normalizeRole(FirestoreParse.stringField(map['role'])),
      shopId: FirestoreParse.stringField(map['shopId']),
      status: _normalizeStatus(map['status']),
      createdAt: FirestoreParse.dateTimeField(map['createdAt']),
    );
  }

  static UserModel? tryFromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final user = UserModel.fromMap(map);
    if (user.userId.isEmpty) return null;
    return user;
  }

  static UserModel? tryFromDocument(DocumentSnapshot doc) {
    return FirestoreParse.tryParse(
      doc,
      UserModel.fromMap,
      validate: (u) => u.userId.isNotEmpty,
    );
  }

  static UserModel? tryFromQueryDocument(QueryDocumentSnapshot doc) {
    return FirestoreParse.tryParseQuery(
      doc,
      UserModel.fromMap,
      validate: (u) => u.userId.isNotEmpty,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'shopId': shopId,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  UserModel copyWith({
    String? userId,
    String? name,
    String? email,
    String? phone,
    String? role,
    String? shopId,
    String? status,
    DateTime? createdAt,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      shopId: shopId ?? this.shopId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
