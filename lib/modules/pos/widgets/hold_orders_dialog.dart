import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/cart_controller.dart';

/// Modal dialog allowing cashiers to view, recall, and manage parked orders (held carts)
class HoldOrdersDialog extends StatelessWidget {
  const HoldOrdersDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const HoldOrdersDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cartController = Get.find<CartController>();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.pause_circle_filled, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Parked Orders (On Hold)'),
          const Spacer(),
          Obx(
            () => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${cartController.parkedCount} / 5',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Obx(() {
          final parked = cartController.parkedCarts;

          if (parked.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No parked orders',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use "Hold Bill" on the cart to temporarily save an order.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: parked.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final cart = parked[index];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                cart.label,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Text(
                              '₹${cart.totalAmount.toStringAsFixed(2)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${cart.parkedAt.hour.toString().padLeft(2, '0')}:${cart.parkedAt.minute.toString().padLeft(2, '0')} • ${cart.itemCount} items',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.outline,
                              ),
                            ),
                            if (cart.customerMobile.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Icon(
                                Icons.phone,
                                size: 14,
                                color: colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                cart.customerMobile,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                cartController.discardParkedCart(cart.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('${cart.label} deleted'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Discard'),
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.error,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () {
                                final success =
                                    cartController.recallCart(cart.id);
                                if (success) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${cart.label} recalled to cart',
                                      ),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.restore, size: 18),
                              label: const Text('Recall Order'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
