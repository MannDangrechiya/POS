import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/observability/error_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../authentication/auth_controller.dart';
import 'admin_controller.dart';
import '../products/product_list_screen.dart';
import 'inventory/inventory_screen.dart';
import 'inventory/low_stock_alerts_screen.dart';
import '../inventory/inventory_adjustment_screen.dart';
import 'employees/employee_list_screen.dart';
import 'categories/category_list_screen.dart';
import '../expenses/expense_screen.dart';
import '../reports/reports_dashboard.dart';
import '../reports/reports_service.dart';
import '../reports/sales_report_screen.dart';
import '../reports/product_sales_report_screen.dart';
import '../reports/employee_performance_screen.dart';
import '../reports/expense_report_screen.dart';
import '../orders/order_history_screen.dart';
import 'customers/customer_list_screen.dart';
import 'audit_logs_screen.dart';
import 'settings_screen.dart';
import '../../data/models/order_model.dart';
import '../../data/models/user_model.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/screen_permission.dart';

/// Admin Dashboard - Entry screen for admin users
/// Displays today's sales, order count, low-stock alerts, recent orders; navigation to modules.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _loading = true;
  double _todaySales = 0;
  int _todayOrderCount = 0;
  int _lowStockCount = 0;
  double _totalRevenue = 0;
  int _activeEmployeeCount = 0;
  List<OrderModel> _recentOrders = [];
  Timer? _refreshTimer;

  // Requirement in Detail §25.4: "Data refreshes automatically."
  static const _refreshInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _loadUserAndSummary();
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => _loadUserAndSummary(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserAndSummary({bool silent = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!silent) setState(() => _loading = false);
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      if (!userDoc.exists) {
        if (!silent) setState(() => _loading = false);
        return;
      }
      final userData = UserModel.tryFromDocument(userDoc);
      if (userData == null) {
        if (!silent) setState(() => _loading = false);
        return;
      }
      final shopId = userData.shopId;

      final reports = ReportsService();
      final summary = await reports.getTodaySalesSummary(
        shopId: shopId.isEmpty ? null : shopId,
      );
      int lowStock = 0;
      double totalRevenue = 0;
      int activeEmployees = 0;
      if (shopId.isNotEmpty) {
        lowStock = await reports.getLowStockCount(shopId: shopId);
        totalRevenue = await reports.getTotalRevenue(shopId: shopId);
        activeEmployees = await reports.getActiveEmployeeCount(
          shopId: shopId,
        );
      } else {
        totalRevenue = await reports.getTotalRevenue();
      }
      final recent = await reports.getRecentLockedOrders(
        shopId: shopId.isEmpty ? null : shopId,
        limit: 5,
      );
      if (!mounted) return;
      setState(() {
        _todaySales = (summary['totalSales'] as num?)?.toDouble() ?? 0;
        _todayOrderCount = summary['orderCount'] as int? ?? 0;
        _lowStockCount = lowStock;
        _totalRevenue = totalRevenue;
        _activeEmployeeCount = activeEmployees;
        _recentOrders = recent;
        _loading = false;
      });
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'AdminDashboard._loadDashboard');
      if (!mounted) return;
      if (!silent) setState(() => _loading = false);
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!context.mounted) return;
    await AuthController().signOut();
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Widget _buildSummarySection(BuildContext context, ColorScheme colorScheme) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Overview",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Today's Sales",
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${_todaySales.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Orders',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_todayOrderCount',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: 2,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    GuardedNavigator.push(
                      context,
                      permission: ScreenPermission.lowStockAlerts,
                      page: const LowStockAlertsScreen(),
                    );
                  },
                  child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Low Stock',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_lowStockCount',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _lowStockCount > 0
                              ? colorScheme.error
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Revenue',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${_totalRevenue.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Active Employees',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_activeEmployeeCount',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_recentOrders.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Recent Orders',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentOrders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final order = _recentOrders[index];
                return ListTile(
                  title: Text(
                    order.orderId.length > 12
                        ? '${order.orderId.substring(0, 12)}...'
                        : order.orderId,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    '₹${order.totalAmount.toStringAsFixed(0)} • ${order.orderStatus}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    GuardedNavigator.push(
                      context,
                      permission: ScreenPermission.orderHistory,
                      page: const OrderHistoryScreen(),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Get.put(AdminController());
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome section
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.admin_panel_settings,
                          size: 32,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Dashboard',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Manage your shop operations',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Today's overview summary
              _buildSummarySection(context, colorScheme),

              const SizedBox(height: 32),

              // Management modules section
              Text(
                'Management Modules',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Navigation tiles grid
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  _buildNavigationCard(
                    context,
                    title: 'Products',
                    icon: Icons.inventory_2,
                    color: colorScheme.primary,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.productList,
                        page: const ProductListScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Inventory',
                    icon: Icons.warehouse,
                    color: colorScheme.secondary,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.inventory,
                        page: const InventoryScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Employees',
                    icon: Icons.people,
                    color: colorScheme.tertiary,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.employeeList,
                        page: const EmployeeListScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Expenses',
                    icon: Icons.account_balance_wallet,
                    color: colorScheme.error,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.expenseList,
                        page: const ExpenseScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Customers',
                    icon: Icons.person_outline,
                    color: colorScheme.primaryContainer,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.customerList,
                        page: const CustomerListScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Categories',
                    icon: Icons.category,
                    color: colorScheme.secondaryContainer,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.categoryList,
                        page: const CategoryListScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Inventory Adjustment',
                    icon: Icons.tune,
                    color: colorScheme.tertiaryContainer,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.inventoryAdjustment,
                        page: const InventoryAdjustmentScreen(),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Reports section
              Text(
                'Reports & Analytics',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              _buildReportsCard(context),
              const SizedBox(height: 16),
              // Dedicated reports tiles
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.2,
                children: [
                  _buildNavigationCard(
                    context,
                    title: 'Sales Reports',
                    icon: Icons.bar_chart,
                    color: colorScheme.primary,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.salesReport,
                        page: const SalesReportScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Product Reports',
                    icon: Icons.insights,
                    color: colorScheme.secondary,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.productSalesReport,
                        page: const ProductSalesReportScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Employee Reports',
                    icon: Icons.people_alt,
                    color: colorScheme.tertiary,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.employeePerformanceReport,
                        page: const EmployeePerformanceScreen(),
                      );
                    },
                  ),
                  _buildNavigationCard(
                    context,
                    title: 'Expense Reports',
                    icon: Icons.account_balance_wallet,
                    color: colorScheme.error,
                    onTap: () {
                      GuardedNavigator.push(
                        context,
                        permission: ScreenPermission.expenseReport,
                        page: const ExpenseReportScreen(),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildOrderHistoryCard(context),
              const SizedBox(height: 16),
              _buildAuditLogsCard(context),
              const SizedBox(height: 16),
              _buildSettingsCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 26, color: color),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          GuardedNavigator.push(
            context,
            permission: ScreenPermission.reportsDashboard,
            page: const ReportsDashboard(),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.analytics,
                  size: 32,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reports & Analytics',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View sales reports and business insights',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderHistoryCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          GuardedNavigator.push(
            context,
            permission: ScreenPermission.orderHistory,
            page: const OrderHistoryScreen(),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long,
                  size: 32,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'List orders, view details, cancel pending',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditLogsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          GuardedNavigator.push(
            context,
            permission: ScreenPermission.auditLogs,
            page: const AuditLogsScreen(),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history,
                  size: 32,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Audit Logs',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'View activity and compliance logs',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          GuardedNavigator.push(
            context,
            permission: ScreenPermission.adminSettings,
            page: const SettingsScreen(),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.settings,
                  size: 32,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Shop and operational settings',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
