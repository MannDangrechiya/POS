import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_pagination.dart';
import '../../core/firestore/firestore_parse.dart';
import '../../core/firestore/firestore_stream_cache.dart';
import '../../data/models/order_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/product_model.dart';

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

  /// Comprehensive wholesale & retail margin analytics, spoilage loss, khata exposure,
  /// and multi-terminal performance breakdown.
  Future<WholesaleAnalyticsData> getWholesaleAnalytics({
    required DateTime start,
    required DateTime end,
    String? shopId,
  }) async {
    final orders = await getLockedOrdersInRangeBatched(
      start: start,
      end: end,
      shopId: shopId,
    );

    double totalRevenue = 0.0;
    double totalCost = 0.0;
    final Map<String, _ProdAcc> prodMap = {};
    final Map<String, double> terminalMap = {};

    int retailOrders = 0;
    double retailRev = 0.0;
    int wholesaleTier1Orders = 0;
    double wholesaleTier1Rev = 0.0;
    int wholesaleTier2Orders = 0;
    double wholesaleTier2Rev = 0.0;

    final Map<String, ProductModel?> prodCache = {};

    for (final order in orders) {
      totalRevenue += order.totalAmount;
      final term = order.terminalId.isNotEmpty ? order.terminalId : 'REG-01';
      terminalMap[term] = (terminalMap[term] ?? 0.0) + order.totalAmount;

      final items = await getOrderItems(order.orderId);
      double orderTotalKg = 0.0;

      for (final it in items) {
        final pid = it['productId'] as String? ?? '';
        if (pid.isEmpty) continue;
        final qty = (it['quantityOrWeight'] as num?)?.toDouble() ?? 0.0;
        final itemTotal = (it['totalPrice'] as num?)?.toDouble() ?? 0.0;
        orderTotalKg += qty;

        if (!prodCache.containsKey(pid)) {
          final pDoc = await _db.collection('products').doc(pid).get();
          prodCache[pid] = ProductModel.tryFromDocument(pDoc);
        }
        final product = prodCache[pid];
        final costPerUnit = product?.costPrice ?? 0.0;
        final effectiveCost = (costPerUnit > 0) ? costPerUnit * qty : 0.0;
        totalCost += effectiveCost;

        final acc = prodMap.putIfAbsent(
          pid,
          () => _ProdAcc(name: product?.name ?? pid, category: product?.categoryId ?? ''),
        );
        acc.quantitySold += qty;
        acc.revenue += itemTotal;
        acc.cost += effectiveCost;
      }

      if (orderTotalKg >= 50) {
        wholesaleTier2Orders++;
        wholesaleTier2Rev += order.totalAmount;
      } else if (orderTotalKg >= 10) {
        wholesaleTier1Orders++;
        wholesaleTier1Rev += order.totalAmount;
      } else {
        retailOrders++;
        retailRev += order.totalAmount;
      }
    }

    final grossProfit = totalRevenue - totalCost;
    final grossMarginPercent = totalRevenue > 0 ? (grossProfit / totalRevenue) * 100 : 0.0;

    final productMargins = prodMap.entries.map((e) {
      final p = e.value;
      final profit = p.revenue - p.cost;
      final marginPct = p.revenue > 0 ? (profit / p.revenue) * 100 : 0.0;
      return ProductMarginItem(
        productId: e.key,
        name: p.name,
        category: p.category,
        quantitySold: p.quantitySold,
        revenue: p.revenue,
        totalCost: p.cost,
        grossProfit: profit,
        marginPercent: marginPct,
      );
    }).toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    // Spoilage / Wastage
    double totalSpoilageLoss = 0.0;
    final Map<String, SpoilageItem> spoilageMap = {};

    try {
      Query<Map<String, dynamic>> refQ = _db
          .collection('refunds')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end));
      if (shopId != null && shopId.isNotEmpty) {
        refQ = refQ.where('shopId', isEqualTo: shopId);
      }
      final refSnap = await refQ.get();
      for (final doc in refSnap.docs) {
        final data = doc.data();
        final rawItems = data['items'] as List<dynamic>? ?? [];
        for (final raw in rawItems) {
          if (raw is Map) {
            final disp = (raw['disposition'] as String? ?? '').toLowerCase();
            if (disp == 'damaged') {
              final pid = raw['productId'] as String? ?? '';
              final pName = raw['productName'] as String? ?? 'Damaged Fruit';
              final q = (raw['quantityReturned'] as num?)?.toDouble() ?? 0.0;
              final loss = (raw['refundAmount'] as num?)?.toDouble() ?? 0.0;
              final reason = raw['reason'] as String? ?? 'Spoiled';

              totalSpoilageLoss += loss;
              final existing = spoilageMap[pid];
              if (existing == null) {
                spoilageMap[pid] = SpoilageItem(
                  productId: pid,
                  name: pName,
                  quantityDamaged: q,
                  lossAmount: loss,
                  reasons: [reason],
                );
              } else {
                spoilageMap[pid] = SpoilageItem(
                  productId: pid,
                  name: pName,
                  quantityDamaged: existing.quantityDamaged + q,
                  lossAmount: existing.lossAmount + loss,
                  reasons: {...existing.reasons, reason}.toList(),
                );
              }
            }
          }
        }
      }
    } catch (_) {}

    final spoilageRate = totalRevenue > 0 ? (totalSpoilageLoss / totalRevenue) * 100 : 0.0;

    // Outstanding Khata Balances
    double totalOutstandingCredit = 0.0;
    final List<KhataDebtorItem> debtors = [];

    try {
      Query<Map<String, dynamic>> custQ = _db.collection('customers');
      if (shopId != null && shopId.isNotEmpty) {
        custQ = custQ.where('shopId', isEqualTo: shopId);
      }
      custQ = custQ.where('currentBalance', isGreaterThan: 0);
      final custSnap = await custQ.get();
      for (final doc in custSnap.docs) {
        final d = doc.data();
        final bal = (d['currentBalance'] as num?)?.toDouble() ?? 0.0;
        final lim = (d['creditLimit'] as num?)?.toDouble() ?? 10000.0;
        final util = lim > 0 ? (bal / lim) * 100 : 0.0;
        totalOutstandingCredit += bal;
        debtors.add(
          KhataDebtorItem(
            customerId: doc.id,
            name: d['name'] as String? ?? 'Customer',
            mobile: d['mobile'] as String? ?? '',
            currentBalance: bal,
            creditLimit: lim,
            utilizationPercent: util,
          ),
        );
      }
      debtors.sort((a, b) => b.currentBalance.compareTo(a.currentBalance));
    } catch (_) {}

    final totalVolRev = retailRev + wholesaleTier1Rev + wholesaleTier2Rev;
    final volumeTiers = [
      WholesaleVolumeTier(
        tierName: 'Retail (<10 kg)',
        orderCount: retailOrders,
        totalRevenue: retailRev,
        percentage: totalVolRev > 0 ? (retailRev / totalVolRev) * 100 : 0.0,
      ),
      WholesaleVolumeTier(
        tierName: 'Wholesale Tier 1 (10-50 kg)',
        orderCount: wholesaleTier1Orders,
        totalRevenue: wholesaleTier1Rev,
        percentage: totalVolRev > 0 ? (wholesaleTier1Rev / totalVolRev) * 100 : 0.0,
      ),
      WholesaleVolumeTier(
        tierName: 'Wholesale Tier 2 (>50 kg Crate)',
        orderCount: wholesaleTier2Orders,
        totalRevenue: wholesaleTier2Rev,
        percentage: totalVolRev > 0 ? (wholesaleTier2Rev / totalVolRev) * 100 : 0.0,
      ),
    ];

    final terminalList = terminalMap.entries
        .map((e) => TerminalPerformanceItem(
              terminalId: e.key,
              orderCount: orders.where((o) => (o.terminalId.isNotEmpty ? o.terminalId : 'REG-01') == e.key).length,
              totalSales: e.value,
            ))
        .toList()
      ..sort((a, b) => b.totalSales.compareTo(a.totalSales));

    return WholesaleAnalyticsData(
      totalRevenue: totalRevenue,
      totalCost: totalCost,
      grossProfit: grossProfit,
      grossMarginPercent: grossMarginPercent,
      totalSpoilageLoss: totalSpoilageLoss,
      spoilageRatePercent: spoilageRate,
      totalOutstandingCredit: totalOutstandingCredit,
      productMargins: productMargins,
      spoilageItems: spoilageMap.values.toList()..sort((a, b) => b.lossAmount.compareTo(a.lossAmount)),
      volumeTiers: volumeTiers,
      debtors: debtors,
      terminalPerformance: terminalList,
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

class _ProdAcc {
  final String name;
  final String category;
  double quantitySold = 0.0;
  double revenue = 0.0;
  double cost = 0.0;

  _ProdAcc({required this.name, required this.category});
}

/// Margin analysis row for a specific fruit product
class ProductMarginItem {
  final String productId;
  final String name;
  final String category;
  final double quantitySold;
  final double revenue;
  final double totalCost;
  final double grossProfit;
  final double marginPercent;

  const ProductMarginItem({
    required this.productId,
    required this.name,
    required this.category,
    required this.quantitySold,
    required this.revenue,
    required this.totalCost,
    required this.grossProfit,
    required this.marginPercent,
  });
}

/// Damaged / spoiled fruit loss row
class SpoilageItem {
  final String productId;
  final String name;
  final double quantityDamaged;
  final double lossAmount;
  final List<String> reasons;

  const SpoilageItem({
    required this.productId,
    required this.name,
    required this.quantityDamaged,
    required this.lossAmount,
    required this.reasons,
  });
}

/// Wholesale volume distribution tier
class WholesaleVolumeTier {
  final String tierName;
  final int orderCount;
  final double totalRevenue;
  final double percentage;

  const WholesaleVolumeTier({
    required this.tierName,
    required this.orderCount,
    required this.totalRevenue,
    required this.percentage,
  });
}

/// Outstanding customer credit / Khata debtor item
class KhataDebtorItem {
  final String customerId;
  final String name;
  final String mobile;
  final double currentBalance;
  final double creditLimit;
  final double utilizationPercent;

  const KhataDebtorItem({
    required this.customerId,
    required this.name,
    required this.mobile,
    required this.currentBalance,
    required this.creditLimit,
    required this.utilizationPercent,
  });
}

/// Multi-register / counter sales breakdown
class TerminalPerformanceItem {
  final String terminalId;
  final int orderCount;
  final double totalSales;

  const TerminalPerformanceItem({
    required this.terminalId,
    required this.orderCount,
    required this.totalSales,
  });
}

/// Aggregated wholesale & margin analytics data
class WholesaleAnalyticsData {
  final double totalRevenue;
  final double totalCost;
  final double grossProfit;
  final double grossMarginPercent;
  final double totalSpoilageLoss;
  final double spoilageRatePercent;
  final double totalOutstandingCredit;
  final List<ProductMarginItem> productMargins;
  final List<SpoilageItem> spoilageItems;
  final List<WholesaleVolumeTier> volumeTiers;
  final List<KhataDebtorItem> debtors;
  final List<TerminalPerformanceItem> terminalPerformance;

  const WholesaleAnalyticsData({
    required this.totalRevenue,
    required this.totalCost,
    required this.grossProfit,
    required this.grossMarginPercent,
    required this.totalSpoilageLoss,
    required this.spoilageRatePercent,
    required this.totalOutstandingCredit,
    required this.productMargins,
    required this.spoilageItems,
    required this.volumeTiers,
    required this.debtors,
    required this.terminalPerformance,
  });

  factory WholesaleAnalyticsData.empty() => const WholesaleAnalyticsData(
        totalRevenue: 0.0,
        totalCost: 0.0,
        grossProfit: 0.0,
        grossMarginPercent: 0.0,
        totalSpoilageLoss: 0.0,
        spoilageRatePercent: 0.0,
        totalOutstandingCredit: 0.0,
        productMargins: [],
        spoilageItems: [],
        volumeTiers: [],
        debtors: [],
        terminalPerformance: [],
      );
}
