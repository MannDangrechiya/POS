import 'package:flutter/material.dart';
import '../../../core/observability/error_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/models/low_stock_alert_model.dart';
import '../../../data/models/user_model.dart';
import '../../../routing/permission_gate.dart';
import '../../../routing/screen_permission.dart';
import '../../../widgets/firestore_paginated_list.dart';

/// Read-only view of currently unresolved low-stock/out-of-stock alerts for
/// Admin (own shop) / Super Admin (all shops). Alerts are raised and
/// auto-resolved only by the onProductStockChange Cloud Function trigger —
/// see low_stock_alert_model.dart for why this exists.
class LowStockAlertsScreen extends StatefulWidget {
  const LowStockAlertsScreen({super.key});

  @override
  State<LowStockAlertsScreen> createState() => _LowStockAlertsScreenState();
}

class _LowStockAlertsScreenState extends State<LowStockAlertsScreen> {
  String? _shopId;
  bool _isSuperAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
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
          _shopId = u.shopId;
          _isSuperAdmin = u.role == 'SuperAdmin';
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'LowStockAlertsScreen._load');
      setState(() => _loading = false);
    }
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('low_stock_alerts')
        .where('resolved', isEqualTo: false);
    if (!_isSuperAdmin && _shopId != null && _shopId!.isNotEmpty) {
      q = q.where('shopId', isEqualTo: _shopId);
    }
    return q.orderBy('createdAt', descending: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PermissionGate(
        permission: ScreenPermission.lowStockAlerts,
        child: Scaffold(
          appBar: AppBar(title: const Text('Low Stock Alerts')),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final cacheKey = _isSuperAdmin
        ? 'low_stock_alerts_all'
        : 'low_stock_alerts_shop_${_shopId ?? ''}';

    return PermissionGate(
      permission: ScreenPermission.lowStockAlerts,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isSuperAdmin ? 'Low Stock Alerts (All shops)' : 'Low Stock Alerts',
          ),
        ),
        body: FirestorePaginatedList<LowStockAlertModel>(
          cacheKey: cacheKey,
          queryBuilder: _buildQuery,
          parse: (data, _) => LowStockAlertModel.tryFromMap(data),
          itemKey: (a) => a.alertId,
          emptyBuilder: (_) => const Center(
            child: Text('No active low-stock alerts — all stock is healthy.'),
          ),
          itemBuilder: (context, alert) => _buildAlertCard(context, alert),
        ),
      ),
    );
  }

  Widget _buildAlertCard(BuildContext context, LowStockAlertModel alert) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = alert.isOutOfStock ? colorScheme.error : colorScheme.errorContainer;
    final onColor = alert.isOutOfStock
        ? colorScheme.onError
        : colorScheme.onErrorContainer;

    return Card(
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(
            alert.isOutOfStock ? Icons.cancel : Icons.warning_amber_rounded,
            color: onColor,
          ),
        ),
        title: Text(
          alert.productName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          alert.isOutOfStock
              ? 'Out of stock (threshold: ${alert.threshold.toStringAsFixed(0)})'
              : 'Stock: ${alert.stock.toStringAsFixed(2)} '
                  '(threshold: ${alert.threshold.toStringAsFixed(0)})',
        ),
        trailing: Text(
          '${alert.createdAt.month.toString().padLeft(2, '0')}/'
          '${alert.createdAt.day.toString().padLeft(2, '0')}',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
