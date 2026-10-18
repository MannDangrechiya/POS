import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/observability/error_ui.dart';
import '../../data/models/user_model.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';
import 'reports_service.dart';

/// Commercial Wholesale & Retail Analytics Screen.
///
/// Features Gross Margin tracking, Cost of Goods Sold (COGS), Spoilage/Wastage
/// Loss analysis, Volume Tier distribution, and Customer Khata exposure.
class WholesaleAnalyticsScreen extends StatefulWidget {
  final String? shopId;
  final String? role;

  const WholesaleAnalyticsScreen({
    super.key,
    this.shopId,
    this.role,
  });

  @override
  State<WholesaleAnalyticsScreen> createState() => _WholesaleAnalyticsScreenState();
}

enum _AnalyticsDateRange { today, week, month }

class _WholesaleAnalyticsScreenState extends State<WholesaleAnalyticsScreen> {
  final ReportsService _reportsService = ReportsService();
  String? _shopId;
  bool _loading = true;
  String? _error;
  _AnalyticsDateRange _selectedRange = _AnalyticsDateRange.month;
  WholesaleAnalyticsData? _data;

  @override
  void initState() {
    super.initState();
    _resolveShopAndLoad();
  }

  Future<void> _resolveShopAndLoad() async {
    if (widget.shopId != null && widget.shopId!.isNotEmpty) {
      _shopId = widget.shopId;
      _loadData();
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final u = UserModel.tryFromDocument(doc);
        if (u != null) {
          _shopId = u.shopId;
        }
      }
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'WholesaleAnalytics._resolveShop');
    }

    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final now = DateTime.now();
    DateTime start;
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (_selectedRange) {
      case _AnalyticsDateRange.today:
        start = DateTime(now.year, now.month, now.day);
        break;
      case _AnalyticsDateRange.week:
        start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
        break;
      case _AnalyticsDateRange.month:
        start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
        break;
    }

    try {
      final res = await _reportsService.getWholesaleAnalytics(
        start: start,
        end: end,
        shopId: _shopId,
      );
      if (mounted) {
        setState(() {
          _data = res;
          _loading = false;
        });
      }
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'WholesaleAnalytics._loadData');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.reportsDashboard,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Wholesale & Margin Analytics'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Analytics',
              onPressed: _loadData,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load analytics: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data ?? WholesaleAnalyticsData.empty();

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          _buildDateRangeSelector(),
          _buildKpiSummary(data),
          const Divider(height: 1),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.pie_chart_outline), text: 'Product Margins'),
              Tab(icon: Icon(Icons.delete_sweep_outlined), text: 'Spoilage & Loss'),
              Tab(icon: Icon(Icons.bar_chart_outlined), text: 'Wholesale Tiers'),
              Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Khata Exposure'),
              Tab(icon: Icon(Icons.point_of_sale_outlined), text: 'Registers'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildProductMarginsTab(data),
                _buildSpoilageTab(data),
                _buildWholesaleTiersTab(data),
                _buildKhataTab(data),
                _buildRegistersTab(data),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SegmentedButton<_AnalyticsDateRange>(
        segments: const [
          ButtonSegment(
            value: _AnalyticsDateRange.today,
            label: Text('Today'),
            icon: Icon(Icons.today),
          ),
          ButtonSegment(
            value: _AnalyticsDateRange.week,
            label: Text('Last 7 Days'),
            icon: Icon(Icons.date_range),
          ),
          ButtonSegment(
            value: _AnalyticsDateRange.month,
            label: Text('Last 30 Days'),
            icon: Icon(Icons.calendar_month),
          ),
        ],
        selected: {_selectedRange},
        onSelectionChanged: (val) {
          if (val.isNotEmpty) {
            setState(() => _selectedRange = val.first);
            _loadData();
          }
        },
      ),
    );
  }

  Widget _buildKpiSummary(WholesaleAnalyticsData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildMetricCard(
            title: 'Gross Revenue',
            value: '₹${data.totalRevenue.toStringAsFixed(2)}',
            subtitle: 'Gross sales',
            color: colorScheme.primary,
            icon: Icons.currency_rupee,
          ),
          const SizedBox(width: 12),
          _buildMetricCard(
            title: 'Cost of Goods (COGS)',
            value: '₹${data.totalCost.toStringAsFixed(2)}',
            subtitle: 'Wholesale product cost',
            color: Colors.blueGrey,
            icon: Icons.inventory_outlined,
          ),
          const SizedBox(width: 12),
          _buildMetricCard(
            title: 'Gross Margin',
            value: '₹${data.grossProfit.toStringAsFixed(2)}',
            subtitle: '${data.grossMarginPercent.toStringAsFixed(1)}% margin',
            color: data.grossProfit >= 0 ? Colors.green[700]! : Colors.red[700]!,
            icon: Icons.trending_up,
          ),
          const SizedBox(width: 12),
          _buildMetricCard(
            title: 'Spoilage Loss',
            value: '₹${data.totalSpoilageLoss.toStringAsFixed(2)}',
            subtitle: '${data.spoilageRatePercent.toStringAsFixed(1)}% of sales',
            color: Colors.red[700]!,
            icon: Icons.report_problem_outlined,
          ),
          const SizedBox(width: 12),
          _buildMetricCard(
            title: 'Customer Khata Debt',
            value: '₹${data.totalOutstandingCredit.toStringAsFixed(2)}',
            subtitle: '${data.debtors.length} active debtors',
            color: Colors.amber[800]!,
            icon: Icons.account_balance,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildProductMarginsTab(WholesaleAnalyticsData data) {
    if (data.productMargins.isEmpty) {
      return const Center(child: Text('No product sales recorded in this period.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: data.productMargins.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final item = data.productMargins[idx];
        final isProfitPositive = item.grossProfit >= 0;
        final marginColor = item.marginPercent >= 25
            ? Colors.green[700]
            : (item.marginPercent >= 15 ? Colors.amber[800] : Colors.red[700]);

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey[300]!),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qty Sold: ${item.quantitySold.toStringAsFixed(2)} | Revenue: ₹${item.revenue.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      Text(
                        'COGS: ₹${item.totalCost.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isProfitPositive ? '+' : ''}₹${item.grossProfit.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isProfitPositive ? Colors.green[800] : Colors.red[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: marginColor?.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${item.marginPercent.toStringAsFixed(1)}% margin',
                          style: TextStyle(
                            color: marginColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSpoilageTab(WholesaleAnalyticsData data) {
    if (data.spoilageItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green[600], size: 48),
            const SizedBox(height: 12),
            const Text(
              'Zero Damaged/Spoiled Produce Recorded!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'All returned items were restocked with 0% spoilage loss.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: data.spoilageItems.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final item = data.spoilageItems[idx];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red[200]!),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Quantity Wasted: ${item.quantityDamaged.toStringAsFixed(2)}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 13),
                      ),
                      if (item.reasons.isNotEmpty)
                        Text(
                          'Reasons: ${item.reasons.join(", ")}',
                          style: TextStyle(color: Colors.red[700], fontSize: 11),
                        ),
                    ],
                  ),
                ),
                Text(
                  '-₹${item.lossAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWholesaleTiersTab(WholesaleAnalyticsData data) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Volume Tier Distribution',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Share of revenue generated by retail walk-ins vs wholesale bulk crate purchases.',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...data.volumeTiers.map((tier) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey[300]!),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tier.tierName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '₹${tier.totalRevenue.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${tier.orderCount} orders',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      Text(
                        '${tier.percentage.toStringAsFixed(1)}% of total sales',
                        style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: (tier.percentage / 100).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 8,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildKhataTab(WholesaleAnalyticsData data) {
    if (data.debtors.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green[600], size: 48),
            const SizedBox(height: 12),
            const Text(
              'No Outstanding Khata Balances',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              'All wholesale customer credit accounts are fully settled.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: data.debtors.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final d = data.debtors[idx];
        final isNearLimit = d.utilizationPercent >= 80;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isNearLimit ? Colors.amber[300]! : Colors.grey[300]!),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo.withValues(alpha: 0.1),
                  child: Text(
                    d.name.isNotEmpty ? d.name[0].toUpperCase() : 'C',
                    style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        d.mobile.isNotEmpty ? d.mobile : 'No Mobile',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Limit: ₹${d.creditLimit.toStringAsFixed(0)} (${d.utilizationPercent.toStringAsFixed(0)}% used)',
                        style: TextStyle(
                          color: isNearLimit ? Colors.amber[900] : Colors.grey[700],
                          fontSize: 11,
                          fontWeight: isNearLimit ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${d.currentBalance.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red[800],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRegistersTab(WholesaleAnalyticsData data) {
    if (data.terminalPerformance.isEmpty) {
      return const Center(child: Text('No terminal sales records in this period.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: data.terminalPerformance.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final t = data.terminalPerformance[idx];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey[300]!),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.terminal),
            ),
            title: Text(
              t.terminalId,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${t.orderCount} orders processed'),
            trailing: Text(
              '₹${t.totalSales.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        );
      },
    );
  }
}
