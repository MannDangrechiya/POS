import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_pagination.dart';
import '../../core/firestore/firestore_parse.dart';
import '../../core/firestore/firestore_stream_cache.dart';
import '../../data/models/order_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/user_model.dart';

/// Role-scoped read-only reports. Uses locked orders only; no data modification.
class ReportsService {
  static const String _ordersLocked = 'locked';
  static const String _ordersPending = 'pending';
  static const String _ordersCancelled = 'cancelled';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream of completed (locked) orders for reports.
  /// [shopId] null = all shops (SuperAdmin); [employeeId] non-null = filter to that employee (Employee role).
  Stream<List<OrderModel>> streamLockedOrders({
    String? shopId,
    String? employeeId,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('orders')
        .where('orderStatus', isEqualTo: _ordersLocked);

    if (shopId != null && shopId.isNotEmpty) {
      q = q.where('shopId', isEqualTo: shopId);
    }
    if (employeeId != null && employeeId.isNotEmpty) {
      q = q.where('employeeId', isEqualTo: employeeId);
    }
    q = q
        .orderBy('createdAt', descending: true)
        .limit(FirestorePageSize.reportStreamCap);

    final cacheKey =
        'locked_orders|shop=${shopId ?? ''}|emp=${employeeId ?? ''}';
    return FirestoreStreamCache.instance.stream(cacheKey, () {
      return q.snapshots().map(
        (snap) =>
            FirestoreParse.parseQueryDocs(snap.docs, OrderModel.tryFromMap),
      );
    });
  }

  /// One-time fetch for date range (for period reports).
  Future<List<OrderModel>> getLockedOrdersInRange({
    required DateTime start,
    required DateTime end,
    String? shopId,
    String? employeeId,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('orders')
        .where('orderStatus', isEqualTo: _ordersLocked)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));

    if (shopId != null && shopId.isNotEmpty) {
      q = q.where('shopId', isEqualTo: shopId);
    }
    if (employeeId != null && employeeId.isNotEmpty) {
      q = q.where('employeeId', isEqualTo: employeeId);
    }
    q = q.orderBy('createdAt', descending: true);

    final snap = await q.get();
    return FirestoreParse.parseQueryDocs(snap.docs, OrderModel.tryFromMap);
  }

  /// Paginated locked orders (reports / global summaries).
  Future<FirestorePage<OrderModel>> fetchLockedOrdersPage({
    String? shopId,
    String? employeeId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = FirestorePageSize.history,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('orders')
        .where('orderStatus', isEqualTo: _ordersLocked);
    if (shopId != null && shopId.isNotEmpty) {
      q = q.where('shopId', isEqualTo: shopId);
    }
    if (employeeId != null && employeeId.isNotEmpty) {
      q = q.where('employeeId', isEqualTo: employeeId);
    }
    q = q.orderBy('createdAt', descending: true);
    return fetchFirestorePage(
      query: q,
      parse: (data, _) => OrderModel.tryFromMap(data),
      pageSize: pageSize,
      startAfter: startAfter,
    );
  }

  /// Locked orders in range with optional [maxDocs] cap (batched report reads).
  Future<List<OrderModel>> getLockedOrdersInRangeBatched({
    required DateTime start,
    required DateTime end,
    String? shopId,
    String? employeeId,
    int maxDocs = 2000,
  }) async {
    final all = <OrderModel>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    const batchSize = 200;
    while (all.length < maxDocs) {
      Query<Map<String, dynamic>> q = _db
          .collection('orders')
          .where('orderStatus', isEqualTo: _ordersLocked)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));
      if (shopId != null && shopId.isNotEmpty) {
        q = q.where('shopId', isEqualTo: shopId);
      }
      if (employeeId != null && employeeId.isNotEmpty) {
        q = q.where('employeeId', isEqualTo: employeeId);
      }
      q = q.orderBy('createdAt', descending: true);
      final page = await fetchFirestorePage(
        query: q,
        parse: (data, _) => OrderModel.tryFromMap(data),
        pageSize: batchSize,
        startAfter: cursor,
      );
      all.addAll(page.items);
      if (!page.hasMore || page.lastDocument == null) break;
      cursor = page.lastDocument;
    }
    return all.length > maxDocs ? all.sublist(0, maxDocs) : all;
  }

  /// Stream all orders for order history (pending + locked + cancelled).
  /// Paginated order history for a shop (all statuses).
  Future<FirestorePage<OrderModel>> fetchOrdersForShopPage({
    required String shopId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = FirestorePageSize.history,
  }) {
    return fetchFirestorePage(
      query: _db
          .collection('orders')
          .where('shopId', isEqualTo: shopId)
          .orderBy('createdAt', descending: true),
      parse: (data, _) => OrderModel.tryFromMap(data),
      pageSize: pageSize,
      startAfter: startAfter,
    );
  }

  /// Paginated order history for SuperAdmin (cross-shop).
  Future<FirestorePage<OrderModel>> fetchAllOrdersPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = FirestorePageSize.history,
  }) {
    return fetchFirestorePage(
      query: _db.collection('orders').orderBy('createdAt', descending: true),
      parse: (data, _) => OrderModel.tryFromMap(data),
      pageSize: pageSize,
      startAfter: startAfter,
    );
  }

  @Deprecated('Use fetchOrdersForShopPage / FirestorePagedList for order history')
  Stream<List<OrderModel>> streamAllOrdersForShop({
    required String shopId,
  }) {
    final cacheKey = 'all_orders_shop|$shopId';
    return FirestoreStreamCache.instance.stream(cacheKey, () {
      return _db
          .collection('orders')
          .where('shopId', isEqualTo: shopId)
          .orderBy('createdAt', descending: true)
          .limit(FirestorePageSize.reportStreamCap)
          .snapshots()
          .map(
            (snap) => FirestoreParse.parseQueryDocs(
              snap.docs,
              OrderModel.tryFromMap,
            ),
          );
    });
  }

  /// Stream all orders for SuperAdmin (cross-shop). No shopId filter.
  @Deprecated('Use fetchAllOrdersPage / FirestorePagedList for order history')
  Stream<List<OrderModel>> streamAllOrdersSuperAdmin() {
    const cacheKey = 'all_orders_superadmin';
    return FirestoreStreamCache.instance.stream(cacheKey, () {
      return _db
          .collection('orders')
          .orderBy('createdAt', descending: true)
          .limit(FirestorePageSize.reportStreamCap)
          .snapshots()
          .map(
            (snap) => FirestoreParse.parseQueryDocs(
              snap.docs,
              OrderModel.tryFromMap,
            ),
          );
    });
  }

  /// Stream expenses for a shop. Pass empty shopId for SuperAdmin (all) - need to fetch all.
  Stream<List<ExpenseModel>> streamExpenses({String? shopId}) {
    if (shopId != null && shopId.isNotEmpty) {
      final cacheKey = 'expenses_shop|$shopId';
      return FirestoreStreamCache.instance.stream(cacheKey, () {
        return _db
            .collection('expenses')
            .where('shopId', isEqualTo: shopId)
            .orderBy('createdAt', descending: true)
            .limit(FirestorePageSize.reportStreamCap)
            .snapshots()
            .map(
              (snap) => FirestoreParse.parseQueryDocs(
                snap.docs,
                ExpenseModel.tryFromMap,
              ),
            );
      });
    }
    const cacheKey = 'expenses_all';
    return FirestoreStreamCache.instance.stream(cacheKey, () {
      return _db
          .collection('expenses')
          .orderBy('createdAt', descending: true)
          .limit(FirestorePageSize.reportStreamCap)
          .snapshots()
          .map(
            (snap) => FirestoreParse.parseQueryDocs(
              snap.docs,
              ExpenseModel.tryFromMap,
            ),
          );
    });
  }

  /// Fetch order items for an order (for product-wise breakdown).
  Future<List<Map<String, dynamic>>> getOrderItems(String orderId) async {
    final snap = await _db
        .collection('order_items')
        .where('orderId', isEqualTo: orderId)
        .get();
    return snap.docs
        .map((d) => FirestoreParse.queryDocumentData(d))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Fetch expenses in date range for summary.
  Future<List<ExpenseModel>> getExpensesInRange({
    required DateTime start,
    required DateTime end,
    String? shopId,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('expenses')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));

    if (shopId != null && shopId.isNotEmpty) {
      q = q.where('shopId', isEqualTo: shopId);
    }
    q = q.orderBy('createdAt', descending: true);

    final snap = await q.get();
    return FirestoreParse.parseQueryDocs(snap.docs, ExpenseModel.tryFromMap);
  }

  /// Paginated expenses for a shop.
  Future<FirestorePage<ExpenseModel>> fetchExpensesPage({
    String? shopId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = FirestorePageSize.standard,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('expenses');
    if (shopId != null && shopId.isNotEmpty) {
      q = q.where('shopId', isEqualTo: shopId);
    }
    q = q.orderBy('createdAt', descending: true);
    return fetchFirestorePage(
      query: q,
      parse: (data, _) => ExpenseModel.tryFromMap(data),
      pageSize: pageSize,
      startAfter: startAfter,
    );
  }

  /// Today's sales summary for admin dashboard (locked orders only).
  /// [shopId] required for Admin; pass null for SuperAdmin (all shops).
  Future<Map<String, dynamic>> getTodaySalesSummary({String? shopId}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final orders = await getLockedOrdersInRange(
      start: start,
      end: end,
      shopId: shopId,
    );
    final totalSales = orders.fold<double>(0, (s, o) => s + o.totalAmount);
    return {
      'totalSales': totalSales,
      'orderCount': orders.length,
    };
  }

  /// All-time total revenue from locked orders (Requirement in Detail §25.2 —
  /// distinct from "today's sales"). Batched the same way as
  /// [getLockedOrdersInRangeBatched] to avoid Firestore's 'in'/pagination caps
  /// on large shops.
  Future<double> getTotalRevenue({String? shopId}) async {
    Query<Map<String, dynamic>> q = _db
        .collection('orders')
        .where('orderStatus', isEqualTo: _ordersLocked);
    if (shopId != null && shopId.isNotEmpty) {
      q = q.where('shopId', isEqualTo: shopId);
    }
    double total = 0;
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      // Descending to match the existing (orderStatus, shopId, createdAt DESC)
      // composite index already used elsewhere in this file — order doesn't
      // matter for a sum, but reusing the existing index avoids requiring a
      // new one.
      var page = q
          .orderBy('createdAt', descending: true)
          .limit(FirestorePageSize.posCatalogCap);
      if (cursor != null) page = page.startAfterDocument(cursor);
      final snap = await page.get();
      if (snap.docs.isEmpty) break;
      for (final doc in snap.docs) {
        total += (doc.data()['totalAmount'] as num?)?.toDouble() ?? 0;
      }
      if (snap.docs.length < FirestorePageSize.posCatalogCap) break;
      cursor = snap.docs.last;
    }
    return total;
  }

  /// Number of active (status: 'Active') Employees for a shop, for the Admin
  /// Dashboard's "active employees" metric (Requirement in Detail §25.2).
  Future<int> getActiveEmployeeCount({required String shopId}) async {
    final snap = await _db
        .collection('users')
        .where('shopId', isEqualTo: shopId)
        .where('role', isEqualTo: 'Employee')
        .where('status', isEqualTo: 'Active')
        .count()
        .get();
    return snap.count ?? 0;
  }

  /// Number of products with low stock (0 < stock <= [threshold]).
  static const int defaultLowStockThreshold = 10;

  Future<int> getLowStockCount({
    required String shopId,
    int threshold = defaultLowStockThreshold,
  }) async {
    final snap = await _db
        .collection('products')
        .where('shopId', isEqualTo: shopId)
        .where('status', isEqualTo: 'Active')
        .limit(FirestorePageSize.posCatalogCap)
        .get();
    int count = 0;
    for (final doc in snap.docs) {
      final stock = (doc.data()['stock'] as num?)?.toDouble() ?? 0;
      if (stock > 0 && stock <= threshold) count++;
    }
    return count;
  }

  /// Recent locked orders for dashboard (default 5).
  Future<List<OrderModel>> getRecentLockedOrders({
    required String? shopId,
    int limit = 5,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('orders')
        .where('orderStatus', isEqualTo: _ordersLocked);
    if (shopId != null && shopId.isNotEmpty) {
      q = q.where('shopId', isEqualTo: shopId);
    }
    q = q.orderBy('createdAt', descending: true).limit(limit);
    final snap = await q.get();
    return FirestoreParse.parseQueryDocs(snap.docs, OrderModel.tryFromMap);
  }

  static bool isPending(String orderStatus) =>
      orderStatus.toLowerCase() == _ordersPending;
  static bool isLocked(String orderStatus) =>
      orderStatus.toLowerCase() == _ordersLocked;
  static bool isCancelled(String orderStatus) =>
      orderStatus.toLowerCase() == _ordersCancelled;

  /// Generic sales summary for arbitrary date range.
  /// Returns total sales, order count, average order value, and payment method breakdown.
  Future<SalesSummary> getSalesSummary({
    required DateTime start,
    required DateTime end,
    String? shopId,
  }) async {
    final orders = await getLockedOrdersInRangeBatched(
      start: start,
      end: end,
      shopId: shopId,
    );

    if (orders.isEmpty) {
      return SalesSummary.empty();
    }

    double totalSales = 0;
    final Map<String, int> methodCounts = {};
    final Map<String, double> methodAmounts = {};

    for (final o in orders) {
      totalSales += o.totalAmount;
      final methodKey = (o.paymentMethod.isNotEmpty
              ? o.paymentMethod.toLowerCase()
              : 'unknown')
          .trim();
      methodCounts[methodKey] = (methodCounts[methodKey] ?? 0) + 1;
      methodAmounts[methodKey] =
          (methodAmounts[methodKey] ?? 0) + o.totalAmount;
    }

    final totalOrders = orders.length;
    final avgOrderValue =
        totalOrders == 0 ? 0.0 : totalSales / totalOrders.toDouble();

    return SalesSummary(
      totalSales: totalSales,
      totalOrders: totalOrders,
      averageOrderValue: avgOrderValue,
      paymentMethodCounts: methodCounts,
      paymentMethodAmounts: methodAmounts,
    );
  }

  /// Aggregated product sales for a date range.
  /// Groups by productId and returns quantity sold and total revenue.
  Future<List<ProductSalesRow>> getProductSales({
    required DateTime start,
    required DateTime end,
    String? shopId,
  }) async {
    final orders = await getLockedOrdersInRangeBatched(
      start: start,
      end: end,
      shopId: shopId,
    );

    if (orders.isEmpty) return [];

    final Map<String, ProductSalesRow> map = {};

    for (final order in orders) {
      final items = await getOrderItems(order.orderId);
      for (final item in items) {
        final pid = item['productId'] as String? ?? '';
        if (pid.isEmpty) continue;
        final qty =
            (item['quantityOrWeight'] as num?)?.toDouble() ?? 0.0;
        final total = (item['totalPrice'] as num?)?.toDouble() ?? 0.0;

        final existing = map[pid];
        if (existing == null) {
          map[pid] = ProductSalesRow(
            productId: pid,
            name: 'Loading...',
            quantity: qty,
            total: total,
          );
        } else {
          map[pid] = existing.copyWith(
            quantity: existing.quantity + qty,
            total: existing.total + total,
          );
        }
      }
    }

    if (map.isEmpty) return [];

    // Resolve product names
    for (final pid in map.keys.toList()) {
      final doc = await _db.collection('products').doc(pid).get();
      final productData = FirestoreParse.documentData(doc);
      final name = productData != null
          ? FirestoreParse.stringField(productData['name'], fallback: pid)
          : pid;
      final existing = map[pid]!;
      map[pid] = existing.copyWith(name: name);
    }

    final list = map.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return list;
  }

  /// Employee performance summary for a date range.
  /// Groups orders by employeeId and computes order count, total sales, and AOV.
  Future<List<EmployeePerformanceRow>> getEmployeePerformance({
    required DateTime start,
    required DateTime end,
    String? shopId,
  }) async {
    final orders = await getLockedOrdersInRangeBatched(
      start: start,
      end: end,
      shopId: shopId,
    );

    if (orders.isEmpty) return [];

    final Map<String, List<OrderModel>> byEmployee = {};
    for (final o in orders) {
      if (o.employeeId.isEmpty) continue;
      byEmployee.putIfAbsent(o.employeeId, () => []).add(o);
    }

    if (byEmployee.isEmpty) return [];

    final List<EmployeePerformanceRow> rows = [];
    for (final entry in byEmployee.entries) {
      final empId = entry.key;
      final empOrders = entry.value;
      final totalSales =
          empOrders.fold<double>(0, (s, o) => s + o.totalAmount);
      final orderCount = empOrders.length;
      final avgOrderValue =
          orderCount == 0 ? 0.0 : totalSales / orderCount.toDouble();

      String name = empOrders.first.employeeName;
      if (name.isEmpty) {
        final userDoc =
            await _db.collection('users').doc(empId).get();
        final u = UserModel.tryFromDocument(userDoc);
        if (u != null && u.name.isNotEmpty) {
          name = u.name;
        } else if (userDoc.exists) {
          name = empId.substring(0, empId.length > 8 ? 8 : empId.length);
        } else {
          name = empId.substring(0, empId.length > 8 ? 8 : empId.length);
        }
      }

      rows.add(
        EmployeePerformanceRow(
          employeeId: empId,
          employeeName: name,
          orderCount: orderCount,
          totalSales: totalSales,
          averageOrderValue: avgOrderValue,
        ),
      );
    }

    rows.sort((a, b) => b.totalSales.compareTo(a.totalSales));
    return rows;
  }

  /// Expense summary for a date range: total and category breakdown.
  Future<ExpenseSummary> getExpenseSummary({
    required DateTime start,
    required DateTime end,
    String? shopId,
  }) async {
    final expenses = await getExpensesInRange(
      start: start,
      end: end,
      shopId: shopId,
    );

    if (expenses.isEmpty) {
      return ExpenseSummary.empty();
    }

    double total = 0;
    final Map<String, double> byCategory = {};

    for (final e in expenses) {
      total += e.amount;
      final cat = (e.category.isNotEmpty ? e.category : 'Other').trim();
      byCategory[cat] = (byCategory[cat] ?? 0) + e.amount;
    }

    return ExpenseSummary(
      totalExpenses: total,
      byCategory: byCategory,
      expenses: expenses,
    );
  }
}

/// Structured sales summary.
class SalesSummary {
  final double totalSales;
  final int totalOrders;
  final double averageOrderValue;
  final Map<String, int> paymentMethodCounts;
  final Map<String, double> paymentMethodAmounts;

  const SalesSummary({
    required this.totalSales,
    required this.totalOrders,
    required this.averageOrderValue,
    required this.paymentMethodCounts,
    required this.paymentMethodAmounts,
  });

  factory SalesSummary.empty() => const SalesSummary(
        totalSales: 0.0,
        totalOrders: 0,
        averageOrderValue: 0.0,
        paymentMethodCounts: <String, int>{},
        paymentMethodAmounts: <String, double>{},
      );
}

/// Aggregated product sales row.
class ProductSalesRow {
  final String productId;
  final String name;
  final double quantity;
  final double total;

  const ProductSalesRow({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
  });

  ProductSalesRow copyWith({
    String? productId,
    String? name,
    double? quantity,
    double? total,
  }) {
    return ProductSalesRow(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      total: total ?? this.total,
    );
  }
}

/// Employee performance row.
class EmployeePerformanceRow {
  final String employeeId;
  final String employeeName;
  final int orderCount;
  final double totalSales;
  final double averageOrderValue;

  const EmployeePerformanceRow({
    required this.employeeId,
    required this.employeeName,
    required this.orderCount,
    required this.totalSales,
    required this.averageOrderValue,
  });
}

/// Expense summary with category breakdown.
class ExpenseSummary {
  final double totalExpenses;
  final Map<String, double> byCategory;
  final List<ExpenseModel> expenses;

  const ExpenseSummary({
    required this.totalExpenses,
    required this.byCategory,
    required this.expenses,
  });

  factory ExpenseSummary.empty() =>
      const ExpenseSummary(
        totalExpenses: 0.0,
        byCategory: <String, double>{},
        expenses: <ExpenseModel>[],
      );
}
