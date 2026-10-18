import 'package:flutter/material.dart';
import '../../core/observability/error_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/firestore/firestore_pagination.dart';
import '../../data/models/order_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/user_model.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';
import '../../routing/guarded_navigator.dart';
import 'reports_service.dart';
import 'wholesale_analytics_screen.dart';

/// Full Reports & Analytics. Read-only, shop-scoped by role, locked orders only.
/// Employee: own daily sales. Admin: shop-wide. SuperAdmin: cross-shop. Viewer: read-only.
class ReportsDashboard extends StatefulWidget {
  const ReportsDashboard({
    super.key,
    this.role,
    this.shopId,
    this.userId,
    this.readOnly = false,
  });

  final String? role;
  final String? shopId;
  final String? userId;
  final bool readOnly;

  @override
  State<ReportsDashboard> createState() => _ReportsDashboardState();
}

class _ReportsDashboardState extends State<ReportsDashboard> {
  final ReportsService _reports = ReportsService();
  String? _shopId;
  String? _userId;
  String? _role;
  bool _loading = true;
  Stream<List<OrderModel>>? _lockedOrdersStream;
  Stream<List<ExpenseModel>>? _expensesStream;

  @override
  void initState() {
    super.initState();
    _resolveUser();
  }

  Future<void> _resolveUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    if (widget.shopId != null && widget.userId != null && widget.role != null) {
        setState(() {
          _shopId = widget.shopId;
          _userId = widget.userId;
          _role = widget.role;
          _loading = false;
          _initReportStreams();
        });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final u = UserModel.tryFromDocument(doc);
        if (u == null) {
          setState(() => _loading = false);
          return;
        }
        setState(() {
          _shopId = widget.shopId ?? u.shopId;
          _userId = widget.userId ?? u.userId;
          _role = widget.role ?? u.role;
          _loading = false;
          _initReportStreams();
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'ReportsDashboard._load');
      setState(() => _loading = false);
    }
  }

  bool get _isSuperAdmin =>
      _role != null &&
      _role!.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '') == 'superadmin';
  bool get _isEmployee =>
      _role != null &&
      _role!.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '') == 'employee';

  void _initReportStreams() {
    final shopId = _isSuperAdmin ? null : _shopId;
    final employeeId = _isEmployee ? _userId : null;
    _lockedOrdersStream ??= _reports.streamLockedOrders(
      shopId: shopId,
      employeeId: employeeId,
    );
    _expensesStream ??= _reports.streamExpenses(shopId: shopId);
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.reportsDashboard,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports & Analytics')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.readOnly ? 'Reports (View Only)' : 'Reports & Analytics'),
          actions: [
            FilledButton.tonalIcon(
              onPressed: () {
                GuardedNavigator.push(
                  context,
                  permission: ScreenPermission.reportsDashboard,
                  page: WholesaleAnalyticsScreen(
                    shopId: _isSuperAdmin ? null : _shopId,
                    role: _role,
                  ),
                );
              },
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Wholesale & Margin'),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Live data capped at recent ${FirestorePageSize.reportStreamCap} records per tab',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Sales'),
                    Tab(text: 'Product-wise'),
                    Tab(text: 'Employee'),
                    Tab(text: 'Expenses'),
                    Tab(text: 'Net Profit'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _SalesTab(ordersStream: _lockedOrdersStream!),
            _ProductWiseTab(
              reports: _reports,
              shopId: _isSuperAdmin ? null : _shopId,
              employeeId: _isEmployee ? _userId : null,
            ),
            _EmployeeTab(ordersStream: _lockedOrdersStream!),
            _ExpenseTab(expensesStream: _expensesStream!),
            _NetProfitTab(
              ordersStream: _lockedOrdersStream!,
              expensesStream: _expensesStream!,
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab({required this.ordersStream});

  final Stream<List<OrderModel>> ordersStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: ordersStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final orders = snap.data ?? [];
        final daily = _ordersInRange(orders, DateTime.now(), 1);
        final weekly = _ordersInRange(orders, DateTime.now(), 7);
        final monthly = _ordersInRange(orders, DateTime.now(), 30);

        double sum(List<OrderModel> list) =>
            list.fold(0.0, (s, o) => s + o.totalAmount);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryCard(
                title: 'Daily Sales',
                value: '₹${sum(daily).toStringAsFixed(2)}',
                subtitle: '${daily.length} orders',
                icon: Icons.today,
              ),
              const SizedBox(height: 12),
              _SummaryCard(
                title: 'Weekly Sales',
                value: '₹${sum(weekly).toStringAsFixed(2)}',
                subtitle: '${weekly.length} orders',
                icon: Icons.date_range,
              ),
              const SizedBox(height: 12),
              _SummaryCard(
                title: 'Monthly Sales',
                value: '₹${sum(monthly).toStringAsFixed(2)}',
                subtitle: '${monthly.length} orders',
                icon: Icons.calendar_month,
              ),
            ],
          ),
        );
      },
    );
  }

  List<OrderModel> _ordersInRange(
      List<OrderModel> orders, DateTime end, int days) {
    final start = end.subtract(Duration(days: days));
    return orders
        .where((o) =>
            o.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
            o.createdAt.isBefore(end.add(const Duration(days: 1))))
        .toList();
  }
}

class _ProductWiseTab extends StatefulWidget {
  const _ProductWiseTab({
    required this.reports,
    this.shopId,
    this.employeeId,
  });

  final ReportsService reports;
  final String? shopId;
  final String? employeeId;

  @override
  State<_ProductWiseTab> createState() => _ProductWiseTabState();
}

class _ProductWiseTabState extends State<_ProductWiseTab> {
  final Map<String, _ProductRow> _productMap = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _productMap.clear();
      _loading = true;
      _error = null;
    });
    try {
      final end = DateTime.now();
      final start = end.subtract(const Duration(days: 30));
      final orders = await widget.reports.getLockedOrdersInRange(
        start: start,
        end: end,
        shopId: widget.shopId,
        employeeId: widget.employeeId,
      );
      final map = <String, _ProductRow>{};
      for (final order in orders) {
        final items = await widget.reports.getOrderItems(order.orderId);
        for (final item in items) {
          final pid = item['productId'] as String? ?? '';
          if (pid.isEmpty) continue;
          final qty = (item['quantityOrWeight'] as num?)?.toDouble() ?? 0;
          final total = (item['totalPrice'] as num?)?.toDouble() ?? 0;
          map[pid] = _ProductRow(
            productId: pid,
            name: map[pid]?.name ?? 'Loading...',
            quantity: (map[pid]?.quantity ?? 0) + qty,
            total: (map[pid]?.total ?? 0) + total,
          );
        }
      }
      // Resolve names
      final firestore = FirebaseFirestore.instance;
      for (final pid in map.keys.toList()) {
        final doc = await firestore.collection('products').doc(pid).get();
        final product = ProductModel.tryFromDocument(doc);
        final name = product != null && product.name.isNotEmpty
            ? product.name
            : pid;
        map[pid] = _ProductRow(
          productId: pid,
          name: name,
          quantity: map[pid]!.quantity,
          total: map[pid]!.total,
        );
      }
      setState(() {
        _productMap.addAll(map);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    final list = _productMap.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    if (list.isEmpty) {
      return const Center(child: Text('No product-wise sales in last 30 days'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final r = list[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(r.name),
            subtitle: Text('Qty: ${r.quantity.toStringAsFixed(2)}'),
            trailing: Text(
              '₹${r.total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}

class _ProductRow {
  final String productId;
  final String name;
  final double quantity;
  final double total;
  _ProductRow({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.total,
  });
}

class _EmployeeTab extends StatelessWidget {
  const _EmployeeTab({required this.ordersStream});

  final Stream<List<OrderModel>> ordersStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: ordersStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data ?? [];
        final byEmployee = <String, List<OrderModel>>{};
        for (final o in orders) {
          byEmployee.putIfAbsent(o.employeeId, () => []).add(o);
        }
        final list = byEmployee.entries.toList()
          ..sort((a, b) {
            final sa = a.value.fold(0.0, (s, o) => s + o.totalAmount);
            final sb = b.value.fold(0.0, (s, o) => s + o.totalAmount);
            return sb.compareTo(sa);
          });

        if (list.isEmpty) {
          return const Center(child: Text('No sales data'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final e = list[i];
            final total = e.value.fold(0.0, (s, o) => s + o.totalAmount);
            final name = e.value.first.employeeName.isNotEmpty
                ? e.value.first.employeeName
                : e.key.substring(0, 8);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(name),
                subtitle: Text('${e.value.length} orders'),
                trailing: Text(
                  '₹${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ExpenseTab extends StatelessWidget {
  const _ExpenseTab({required this.expensesStream});

  final Stream<List<ExpenseModel>> expensesStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ExpenseModel>>(
      stream: expensesStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final expenses = snap.data ?? [];
        final total = expenses.fold(0.0, (s, e) => s + e.amount);
        final last30 = DateTime.now().subtract(const Duration(days: 30));
        final recent = expenses
            .where((e) => e.createdAt.isAfter(last30))
            .fold(0.0, (s, e) => s + e.amount);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryCard(
                title: 'Total Expenses (all time)',
                value: '₹${total.toStringAsFixed(2)}',
                subtitle: '${expenses.length} entries',
                icon: Icons.account_balance_wallet,
              ),
              const SizedBox(height: 12),
              _SummaryCard(
                title: 'Last 30 Days',
                value: '₹${recent.toStringAsFixed(2)}',
                subtitle: 'Expenses',
                icon: Icons.trending_down,
              ),
              const SizedBox(height: 16),
              Text(
                'Recent entries',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...expenses.take(20).map(
                    (e) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(e.description.isNotEmpty
                            ? e.description
                            : 'Expense'),
                        subtitle: Text(
                            '${e.createdAt.day}/${e.createdAt.month}/${e.createdAt.year}'),
                        trailing: Text(
                            '₹${e.amount.toStringAsFixed(2)}'),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _NetProfitTab extends StatelessWidget {
  const _NetProfitTab({
    required this.ordersStream,
    required this.expensesStream,
  });

  final Stream<List<OrderModel>> ordersStream;
  final Stream<List<ExpenseModel>> expensesStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: ordersStream,
      builder: (context, orderSnap) {
        return StreamBuilder<List<ExpenseModel>>(
          stream: expensesStream,
          builder: (context, expSnap) {
            if (orderSnap.connectionState == ConnectionState.waiting ||
                expSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final orders = orderSnap.data ?? [];
            final expenses = expSnap.data ?? [];
            final sales = orders.fold(0.0, (s, o) => s + o.totalAmount);
            final expTotal = expenses.fold(0.0, (s, e) => s + e.amount);
            final profit = sales - expTotal;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryCard(
                    title: 'Total Sales',
                    value: '₹${sales.toStringAsFixed(2)}',
                    subtitle: '${orders.length} orders',
                    icon: Icons.currency_rupee,
                  ),
                  const SizedBox(height: 12),
                  _SummaryCard(
                    title: 'Total Expenses',
                    value: '₹${expTotal.toStringAsFixed(2)}',
                    subtitle: '${expenses.length} entries',
                    icon: Icons.account_balance_wallet,
                  ),
                  const SizedBox(height: 12),
                  _SummaryCard(
                    title: 'Net Profit',
                    value: '₹${profit.toStringAsFixed(2)}',
                    subtitle: profit >= 0 ? 'Profit' : 'Loss',
                    icon: Icons.trending_up,
                    valueColor: profit >= 0 ? Colors.green : Colors.red,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.valueColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = valueColor ?? colorScheme.primary;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
