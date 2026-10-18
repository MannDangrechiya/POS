import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/cart_controller.dart';
import '../controllers/shift_controller.dart';
import '../quantity_selection_dialog.dart';
import 'fast_payment_dialog.dart';
import 'hold_orders_dialog.dart';
import 'discount_dialog.dart';
import 'open_shift_dialog.dart';

/// Persistent right-hand cart and fast checkout pane for tablet and desktop POS layouts
class LiveCartPane extends StatelessWidget {
  final String shopId;

  const LiveCartPane({
    super.key,
    required this.shopId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cartController = Get.find<CartController>();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pane Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shopping_cart_checkout,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Current Bill',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // Parked Bills (Hold Orders) Button
                Obx(
                  () => Badge(
                    label: Text('${cartController.parkedCount}'),
                    isLabelVisible: cartController.parkedCount > 0,
                    child: IconButton(
                      icon: const Icon(Icons.receipt_long_outlined),
                      tooltip: 'View Parked Orders',
                      onPressed: () => HoldOrdersDialog.show(context),
                    ),
                  ),
                ),
                // Hold Current Bill Button
                IconButton(
                  icon: const Icon(Icons.pause_circle_outline),
                  tooltip: 'Hold Bill (Park Order)',
                  onPressed: () {
                    if (cartController.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cannot hold an empty bill'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                      return;
                    }
                    final parked = cartController.parkCurrentCart();
                    if (parked) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Order placed on hold'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
                // Discount Button
                IconButton(
                  icon: Obx(
                    () => Icon(
                      Icons.discount_outlined,
                      color: cartController.discountAmount.value > 0
                          ? Colors.indigo
                          : null,
                    ),
                  ),
                  tooltip: 'Order Discount',
                  onPressed: () {
                    if (cartController.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Add items before applying discount'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (_) =>
                          DiscountDialog(cartController: cartController),
                    );
                  },
                ),
                // Clear Cart
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Clear Cart',
                  onPressed: () {
                    if (cartController.isEmpty) return;
                    _showClearCartDialog(context, cartController);
                  },
                ),
              ],
            ),
          ),

          // Customer Quick-Bar
          Obx(() {
            final hasCustomer = cartController.customerMobile.value.isNotEmpty;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: hasCustomer
                  ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(
                    hasCustomer ? Icons.person : Icons.person_outline,
                    size: 18,
                    color: hasCustomer
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasCustomer
                          ? '${cartController.customerName.value} (${cartController.customerMobile.value})'
                          : 'No customer assigned',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: hasCustomer
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showQuickCustomerDialog(context, cartController),
                    child: Text(hasCustomer ? 'Edit' : '+ Customer'),
                  ),
                ],
              ),
            );
          }),

          // Cart Items List
          Expanded(
            child: Obx(() {
              if (cartController.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_shopping_cart_outlined,
                        size: 56,
                        color: colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Cart is empty',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap items or scan barcode to add',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: cartController.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = cartController.items[index];
                  final isWeightBased = item.product.isWeightBased;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Product Name & Unit Price
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.product.name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₹${item.priceSnapshot.toStringAsFixed(2)} / ${item.product.measurementType.toLowerCase()}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Quantity Stepper / Adjuster
                        Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  if (isWeightBased) {
                                    final newQty =
                                        item.quantityOrWeight - 0.25;
                                    if (newQty > 0) {
                                      cartController.updateQuantity(
                                          item.product.productId, newQty);
                                    } else {
                                      cartController.removeItem(
                                          item.product.productId);
                                    }
                                  } else {
                                    final newQty = item.quantityOrWeight - 1;
                                    if (newQty > 0) {
                                      cartController.updateQuantity(
                                          item.product.productId, newQty);
                                    } else {
                                      cartController.removeItem(
                                          item.product.productId);
                                    }
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.remove, size: 16),
                                ),
                              ),
                              InkWell(
                                onTap: () async {
                                  final newQty = await showDialog<double>(
                                    context: context,
                                    builder: (context) =>
                                        QuantitySelectionDialog(
                                      product: item.product,
                                    ),
                                  );
                                  if (newQty != null && newQty > 0) {
                                    cartController.updateQuantity(
                                        item.product.productId, newQty);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  child: Text(
                                    isWeightBased
                                        ? '${item.quantityOrWeight.toStringAsFixed(2)} ${item.product.measurementType.toLowerCase()}'
                                        : '${item.quantityOrWeight.toInt()} ${item.product.measurementType.toLowerCase()}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () {
                                  try {
                                    final step = isWeightBased ? 0.25 : 1.0;
                                    cartController.updateQuantity(
                                      item.product.productId,
                                      item.quantityOrWeight + step,
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e.toString().replaceAll(
                                            'Exception: ', '')),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.add, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Line Total
                        SizedBox(
                          width: 72,
                          child: Text(
                            '₹${item.totalPrice.toStringAsFixed(2)}',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        // Remove
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () => cartController
                              .removeItem(item.product.productId),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ),

          // Total & Fast Checkout Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tax, Discount & Total Summary Breakdown
                Obx(() {
                  final subtotal = cartController.subtotal;
                  final discount = cartController.discountAmount.value;
                  final tax = cartController.taxAmount;
                  final total = cartController.totalAmount;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Subtotal row (if discount or tax is active)
                      if (discount > 0 || tax > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Subtotal (${cartController.itemCount} items)',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              '₹${subtotal.toStringAsFixed(2)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Discount row
                      if (discount > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Discount',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (cartController.discountReason.value.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    '(${cartController.discountReason.value})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.indigo.shade500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              '-₹${discount.toStringAsFixed(2)}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.indigo.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Tax row
                      if (tax > 0) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'GST (${cartController.taxRatePercent.value.toStringAsFixed(0)}%)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              '+₹${tax.toStringAsFixed(2)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],

                      // Final Total Due
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TOTAL DUE',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '₹${total.toStringAsFixed(2)}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 12),

                // Fast Action Buttons
                Obx(() {
                  final hasItems = !cartController.isEmpty;
                  return Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: hasItems
                              ? () => _startPayment(context, 'cash')
                              : null,
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('Cash'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: hasItems
                              ? () => _startPayment(context, 'upi')
                              : null,
                          icon: const Icon(Icons.qr_code, size: 18),
                          label: const Text('UPI QR'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: hasItems
                              ? () => _startPayment(context, 'card')
                              : null,
                          icon: const Icon(Icons.credit_card, size: 18),
                          label: const Text('Card'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _startPayment(BuildContext context, String method) async {
    final shiftCtrl = ShiftController.instance;
    if (!shiftCtrl.hasActiveShift) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final cashierName = userDoc.data()?['name'] ?? user.email ?? 'Cashier';

        if (context.mounted) {
          final opened = await showDialog<bool>(
            context: context,
            builder: (ctx) => OpenShiftDialog(
              shopId: shopId,
              cashierId: user.uid,
              cashierName: cashierName,
            ),
          );
          if (opened != true) return;
        }
      }
    }

    if (context.mounted) {
      FastPaymentDialog.show(
        context,
        shopId: shopId,
        initialPaymentMethod: method,
      );
    }
  }

  void _showClearCartDialog(BuildContext context, CartController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cart'),
        content: const Text('Remove all items from current bill?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              controller.clear();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showQuickCustomerDialog(
      BuildContext context, CartController controller) {
    final mobileCtrl =
        TextEditingController(text: controller.customerMobile.value);
    final nameCtrl = TextEditingController(text: controller.customerName.value);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Customer Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mobileCtrl,
              decoration: const InputDecoration(
                labelText: 'Mobile Number',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Customer Name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          if (controller.customerMobile.value.isNotEmpty)
            TextButton(
              onPressed: () {
                controller.clearCustomer();
                Navigator.pop(ctx);
              },
              child: const Text('Clear'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              controller.setCustomer(nameCtrl.text, mobileCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
