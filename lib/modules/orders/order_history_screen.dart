import 'package:flutter/material.dart';
import '../../core/observability/error_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/firestore/firestore_pagination.dart';
import '../../data/models/order_model.dart';
import '../../data/models/user_model.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';
import '../../widgets/firestore_paginated_list.dart';
import 'order_detail_screen.dart';

/// Admin Order History: paginated shop orders, view details, cancel pending (via CF).
/// Locked orders read-only; no delete.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({
    super.key,
    this.shopId,
    this.readOnly = false,
  });

  final String? shopId;
  /// If true (Viewer), no cancel action.
  final bool readOnly;

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  String? _shopId;
  bool _loading = true;
  bool _isSuperAdmin = false;
  int _listKey = 0;

  @override
  void initState() {
    super.initState();
    _resolveShop();
  }

  Future<void> _resolveShop() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    if (widget.shopId != null && widget.shopId!.isNotEmpty) {
      setState(() {
        _shopId = widget.shopId;
        _loading = false;
      });
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = UserModel.tryFromDocument(doc);
      if (data != null) {
        final role = data.role.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '');
        setState(() {
          _shopId = data.shopId;
          _isSuperAdmin = role == 'superadmin';
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'OrderHistoryScreen._load');
      setState(() => _loading = false);
    }
  }

  Query<Map<String, dynamic>> _ordersQuery() {
    if (_isSuperAdmin) {
      return FirebaseFirestore.instance
          .collection('orders')
          .orderBy('createdAt', descending: true);
    }
    return FirebaseFirestore.instance
        .collection('orders')
        .where('shopId', isEqualTo: _shopId)
        .orderBy('createdAt', descending: true);
  }

  void _refreshList() {
    setState(() => _listKey++);
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.orderHistory,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.readOnly ? 'Order History (View Only)' : 'Order History')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_shopId == null || (_shopId!.isEmpty && !_isSuperAdmin)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order History')),
        body: const Center(child: Text('Shop not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly ? 'Order History (View Only)' : 'Order History'),
      ),
      body: FirestorePagedList<OrderModel>(
        key: ValueKey('order_history_$_listKey'),
        pageSize: FirestorePageSize.history,
        queryBuilder: _ordersQuery,
        parse: (data, _) => OrderModel.tryFromMap(data),
        itemKey: (o) => o.orderId,
        emptyBuilder: (_) => const Center(child: Text('No orders yet')),
        onRefresh: () async => _refreshList(),
        itemBuilder: (context, order) => _OrderCard(
          order: order,
          readOnly: widget.readOnly,
          onTap: () => _showOrderDetail(context, order),
          onCancel: !order.isCancelled && !widget.readOnly
              ? () => _cancelOrder(context, order)
              : null,
        ),
      ),
    );
  }

  void _showOrderDetail(BuildContext context, OrderModel order) {
    GuardedNavigator.push(
      context,
      permission: ScreenPermission.orderDetail,
      page: OrderDetailScreen(
        order: order,
        readOnly: widget.readOnly,
        onCancel: !order.isCancelled && !widget.readOnly
            ? () => _cancelOrder(context, order)
            : null,
      ),
    );
  }

  Future<void> _cancelOrder(BuildContext context, OrderModel order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Text(
          'Cancel order ${order.orderId.substring(0, 8).toUpperCase()}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Order'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('cancelOrder');
      await callable.call(<String, dynamic>{
        'orderId': order.orderId,
        'shopId': order.shopId,
        'reason': 'Cancelled from Admin Order History',
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order cancelled')),
      );
      _refreshList();
    } on FirebaseFunctionsException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.readOnly,
    required this.onTap,
    this.onCancel,
  });

  final OrderModel order;
  final bool readOnly;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = order.isCancelled
        ? Colors.red
        : order.isPending
            ? Colors.orange
            : colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderId.length > 8
                          ? order.orderId.substring(0, 8).toUpperCase()
                          : order.orderId.toUpperCase(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.orderStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year} ${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '₹${order.totalAmount.toStringAsFixed(2)} • ${order.paymentMethod}',
                style: theme.textTheme.bodyMedium,
              ),
              if (onCancel != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel order'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
