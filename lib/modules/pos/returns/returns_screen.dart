import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';

import '../../../data/models/order_model.dart';
import '../../../data/models/refund_model.dart';
import '../../../core/hardware/printer_service.dart';
import '../controllers/shift_controller.dart';

/// Itemized Customer Return, Restock Disposition & Refund Screen
/// Allows cashiers/admins to search past orders, select items to return,
/// assign inventory disposition (restock vs damaged waste), issue refunds,
/// deduct shift cash drawer, and print thermal refund vouchers.
class ReturnsScreen extends StatefulWidget {
  final String shopId;
  final String? initialOrderId;

  const ReturnsScreen({
    super.key,
    required this.shopId,
    this.initialOrderId,
  });

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnItemSelection {
  final String orderItemId;
  final String productId;
  final String productName;
  final double originalQuantity;
  final double unitPrice;
  bool isSelected = false;
  double returnQuantity;
  String disposition = 'restock'; // 'restock' or 'damaged'
  String reason = '';

  _ReturnItemSelection({
    required this.orderItemId,
    required this.productId,
    required this.productName,
    required this.originalQuantity,
    required this.unitPrice,
    this.returnQuantity = 1.0,
  });

  double get refundAmount => returnQuantity * unitPrice;
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final TextEditingController _orderIdController = TextEditingController();
  final TextEditingController _refundReasonController = TextEditingController();

  bool _isLoading = false;
  bool _isProcessing = false;
  OrderModel? _loadedOrder;
  final List<_ReturnItemSelection> _items = [];
  String _selectedRefundMethod = 'cash'; // 'cash', 'original', 'store_credit'

  @override
  void initState() {
    super.initState();
    if (widget.initialOrderId != null && widget.initialOrderId!.isNotEmpty) {
      _orderIdController.text = widget.initialOrderId!;
      _loadOrder(widget.initialOrderId!);
    }
  }

  @override
  void dispose() {
    _orderIdController.dispose();
    _refundReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadOrder(String orderId) async {
    final cleanId = orderId.trim();
    if (cleanId.isEmpty) return;

    setState(() {
      _isLoading = true;
      _loadedOrder = null;
      _items.clear();
    });

    try {
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(cleanId)
          .get();

      if (!orderDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order not found! Please verify Order ID.')),
          );
        }
        return;
      }

      final orderData = orderDoc.data()!;
      if (orderData['shopId'] != widget.shopId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order does not belong to this store!')),
          );
        }
        return;
      }

      final order = OrderModel.fromMap(orderData);

      // Load order items
      final itemsSnap = await FirebaseFirestore.instance
          .collection('order_items')
          .where('orderId', isEqualTo: cleanId)
          .get();

      final List<_ReturnItemSelection> selections = [];
      for (final doc in itemsSnap.docs) {
        final d = doc.data();
        final productId = d['productId'] as String? ?? '';
        final qty = (d['quantityOrWeight'] as num?)?.toDouble() ?? 1.0;
        final price = (d['priceSnapshot'] as num?)?.toDouble() ?? 0.0;

        // Fetch product name
        String pName = 'Item $productId';
        try {
          final pDoc = await FirebaseFirestore.instance.collection('products').doc(productId).get();
          if (pDoc.exists) {
            pName = pDoc.data()?['name'] as String? ?? pName;
          }
        } catch (_) {}

        selections.add(_ReturnItemSelection(
          orderItemId: doc.id,
          productId: productId,
          productName: pName,
          originalQuantity: qty,
          unitPrice: price,
          returnQuantity: qty > 1 ? 1.0 : qty,
        ));
      }

      if (mounted) {
        setState(() {
          _loadedOrder = order;
          _items.addAll(selections);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading order: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  double get _totalRefundAmount {
    return _items
        .where((i) => i.isSelected)
        .fold(0.0, (acc, item) => acc + item.refundAmount);
  }

  Future<void> _processRefund() async {
    final selectedItems = _items.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item to return.')),
      );
      return;
    }

    if (_loadedOrder == null) return;

    setState(() => _isProcessing = true);

    try {
      final activeShiftId = Get.isRegistered<ShiftController>()
          ? ShiftController.instance.activeShift.value?.shiftId
          : null;

      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('processRefund');

      final payload = {
        'orderId': _loadedOrder!.orderId,
        'shopId': widget.shopId,
        'refundMethod': _selectedRefundMethod,
        'reason': _refundReasonController.text.trim().isNotEmpty
            ? _refundReasonController.text.trim()
            : 'Customer Return',
        'shiftId': ?activeShiftId,
        'items': selectedItems
            .map((item) => {
                  'productId': item.productId,
                  'quantity': item.returnQuantity,
                  'disposition': item.disposition,
                  'reason': item.reason.isNotEmpty ? item.reason : 'Return',
                })
            .toList(),
      };

      final result = await callable.call(payload);

      if (result.data['success'] == true) {
        final refundId = result.data['refundId'] as String;
        final totalRefunded = (result.data['totalRefundAmount'] as num).toDouble();

        // Build RefundModel for thermal receipt
        final refundModel = RefundModel(
          refundId: refundId,
          orderId: _loadedOrder!.orderId,
          shopId: widget.shopId,
          employeeId: _loadedOrder!.employeeId,
          refundMethod: _selectedRefundMethod,
          totalRefundAmount: totalRefunded,
          items: selectedItems
              .map((i) => RefundItem(
                    productId: i.productId,
                    productName: i.productName,
                    quantityReturned: i.returnQuantity,
                    unitPrice: i.unitPrice,
                    refundAmount: i.refundAmount,
                    disposition: i.disposition,
                    reason: i.reason,
                  ))
              .toList(),
          reason: _refundReasonController.text.trim(),
          createdAt: DateTime.now(),
        );

        // Auto print refund ticket
        await PrinterService.instance.printRefundTicket(refundModel);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Refund of ₹${totalRefunded.toStringAsFixed(2)} processed successfully! Receipt printed.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          // Reload order to reflect updated status
          _loadOrder(_loadedOrder!.orderId);
        }
      } else {
        throw Exception(result.data['error'] ?? 'Refund processing failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refund failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Itemized Returns & Refunds'),
      ),
      body: Column(
        children: [
          // Order Lookup Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _orderIdController,
                    decoration: InputDecoration(
                      hintText: 'Enter or scan Order ID / Receipt Barcode...',
                      prefixIcon: const Icon(Icons.qr_code_scanner),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    onSubmitted: (val) => _loadOrder(val),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _isLoading ? null : () => _loadOrder(_orderIdController.text),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Search'),
                ),
              ],
            ),
          ),

          // Main Return Body
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_loadedOrder == null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_return_outlined, size: 64, color: colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      'Search an Order ID or scan receipt barcode to begin return',
                      style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Order Summary Header
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Order: ${_loadedOrder!.orderId}',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Chip(
                                label: Text(
                                  _loadedOrder!.orderStatus.toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                backgroundColor: _loadedOrder!.orderStatus == 'refunded'
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : Colors.blue.withValues(alpha: 0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Original Total: ₹${_loadedOrder!.totalAmount.toStringAsFixed(2)} | Method: ${_loadedOrder!.paymentMethod.toUpperCase()}'),
                          Text('Customer: ${_loadedOrder!.customerName} (${_loadedOrder!.customerId})'),
                          Text('Date: ${_loadedOrder!.createdAt.day}/${_loadedOrder!.createdAt.month}/${_loadedOrder!.createdAt.year} ${_loadedOrder!.createdAt.hour}:${_loadedOrder!.createdAt.minute.toString().padLeft(2, '0')}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Select Items to Return',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // Items List
                  ..._items.map((item) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: item.isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                          width: item.isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            CheckboxListTile(
                              value: item.isSelected,
                              onChanged: (val) {
                                setState(() => item.isSelected = val ?? false);
                              },
                              title: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.productName,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Text(
                                    '₹${item.refundAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: item.isSelected ? colorScheme.primary : null,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Original Qty: ${item.originalQuantity} @ ₹${item.unitPrice.toStringAsFixed(2)} each',
                              ),
                            ),
                            if (item.isSelected) ...[
                              const Divider(),
                              Row(
                                children: [
                                  const Text('Return Qty: '),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: item.returnQuantity > 1.0
                                        ? () => setState(() => item.returnQuantity -= 1.0)
                                        : null,
                                  ),
                                  Text(
                                    item.returnQuantity.toStringAsFixed(item.originalQuantity % 1 == 0 ? 0 : 2),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: item.returnQuantity < item.originalQuantity
                                        ? () => setState(() => item.returnQuantity += 1.0)
                                        : null,
                                  ),
                                  const Spacer(),
                                  const Text('Disposition: '),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(value: 'restock', label: Text('Restock')),
                                      ButtonSegment(value: 'damaged', label: Text('Damaged')),
                                    ],
                                    selected: {item.disposition},
                                    onSelectionChanged: (set) {
                                      setState(() => item.disposition = set.first);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),

                  // Refund Options Card
                  Card(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Refund Payment Method', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _refundMethodChip('cash', '💵 Cash'),
                              const SizedBox(width: 8),
                              _refundMethodChip('original', '💳 Original Payment'),
                              const SizedBox(width: 8),
                              _refundMethodChip('store_credit', '📒 Store Credit'),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _refundReasonController,
                            decoration: const InputDecoration(
                              labelText: 'Return Reason (e.g. Overripe, Defective, Wrong item)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Refund Payable:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text(
                                '₹${_totalRefundAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: (_isProcessing || _totalRefundAmount <= 0) ? null : _processRefund,
                              icon: _isProcessing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.assignment_return),
                              label: Text('Issue Refund (₹${_totalRefundAmount.toStringAsFixed(2)}) & Print Voucher'),
                              style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _refundMethodChip(String method, String label) {
    final isSelected = _selectedRefundMethod == method;
    return Expanded(
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          if (val) setState(() => _selectedRefundMethod = method);
        },
      ),
    );
  }
}
