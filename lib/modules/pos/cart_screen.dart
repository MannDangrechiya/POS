import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'controllers/cart_controller.dart';
import 'controllers/shift_controller.dart';
import 'widgets/discount_dialog.dart';
import 'widgets/open_shift_dialog.dart';
import 'quantity_selection_dialog.dart';
import 'customer_screen.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';

/// Cart Summary Screen - Review and adjust cart items before checkout
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.cart,
      child: _buildCart(context),
    );
  }

  Widget _buildCart(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cart'), elevation: 0),
      body: Obx(() {
        final cartController = Get.find<CartController>();

        if (cartController.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 80,
                  color: colorScheme.outline,
                ),
                const SizedBox(height: 24),
                Text('Your cart is empty', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Add products to get started',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.shopping_bag),
                  label: const Text('Browse Products'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Cart items list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: cartController.items.length,
                itemBuilder: (context, index) {
                  final item = cartController.items[index];
                  return _CartItemCard(
                    item: item,
                    onQuantityUpdate: (newQuantity) {
                      try {
                        cartController.updateQuantity(
                          item.product.productId,
                          newQuantity,
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceAll('Exception: ', ''),
                            ),
                            backgroundColor: colorScheme.error,
                          ),
                        );
                      }
                    },
                    onRemove: () {
                      cartController.removeItem(item.product.productId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${item.product.name} removed'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    onEdit: () async {
                      final quantity = await showDialog<double>(
                        context: context,
                        builder: (context) =>
                            QuantitySelectionDialog(product: item.product),
                      );

                      if (quantity != null && quantity > 0) {
                        try {
                          cartController.updateQuantity(
                            item.product.productId,
                            quantity,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceAll('Exception: ', ''),
                                ),
                                backgroundColor: colorScheme.error,
                              ),
                            );
                          }
                        }
                      }
                    },
                  );
                },
              ),
            ),

            // Cart summary and checkout
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Subtotal
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
                        '₹${cartController.subtotal.toStringAsFixed(2)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  // Discount Row
                  if (cartController.discountAmount.value > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Discount (${cartController.discountReason.value})',
                          style: TextStyle(color: Colors.indigo.shade700, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '-₹${cartController.discountAmount.value.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.indigo.shade700, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],

                  // Tax Row
                  if (cartController.taxAmount > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'GST (${cartController.taxRatePercent.value.toStringAsFixed(0)}%)',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        Text(
                          '+₹${cartController.taxAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 8),
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
                        '₹${cartController.totalAmount.toStringAsFixed(2)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Apply Discount Button
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => DiscountDialog(cartController: cartController),
                            );
                          },
                          icon: const Icon(Icons.discount_outlined, size: 18),
                          label: Text(cartController.discountAmount.value > 0 ? 'Edit Discount' : 'Apply Discount'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Checkout button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final shiftCtrl = ShiftController.instance;
                        if (!shiftCtrl.hasActiveShift) {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
                            final cashierName = userDoc.data()?['name'] ?? user.email ?? 'Cashier';
                            final shopId = userDoc.data()?['shopId'] ?? '';

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
                          GuardedNavigator.push(
                            context,
                            permission: ScreenPermission.customerSelect,
                            page: const CustomerScreen(),
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        'Proceed to Checkout (${cartController.itemCount} ${cartController.itemCount == 1 ? 'item' : 'items'})',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final CartItem item;
  final ValueChanged<double> onQuantityUpdate;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _CartItemCard({
    required this.item,
    required this.onQuantityUpdate,
    required this.onRemove,
    required this.onEdit,
  });

  String _getMeasurementUnit() {
    return item.product.measurementType.toLowerCase();
  }

  bool get _isWeightBased {
    final type = item.product.measurementType.toLowerCase();
    return type == 'kg' || type == 'gm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Product icon
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.shopping_bag,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            // Product details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.product.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${item.priceSnapshot.toStringAsFixed(2)} per ${_getMeasurementUnit()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Quantity controls (compact for narrow cart column on phones)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed:
                            item.quantityOrWeight <= (_isWeightBased ? 0.1 : 1)
                            ? null
                            : () => onQuantityUpdate(
                                item.quantityOrWeight -
                                    (_isWeightBased ? 0.1 : 1),
                              ),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${item.quantityOrWeight.toStringAsFixed(_isWeightBased ? 2 : 0)} ${_getMeasurementUnit()}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: item.quantityOrWeight >= item.product.stock
                            ? null
                            : () => onQuantityUpdate(
                                item.quantityOrWeight +
                                    (_isWeightBased ? 0.1 : 1),
                              ),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: onEdit,
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Edit quantity',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Price and remove
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${item.totalPrice.toStringAsFixed(2)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                  onPressed: onRemove,
                  tooltip: 'Remove item',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
