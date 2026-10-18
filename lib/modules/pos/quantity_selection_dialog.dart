import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../data/models/product_model.dart';
import '../../core/hardware/weighing_scale_service.dart';

/// Dialog for selecting quantity or weight for a product
class QuantitySelectionDialog extends StatefulWidget {
  final ProductModel product;

  const QuantitySelectionDialog({
    super.key,
    required this.product,
  });

  @override
  State<QuantitySelectionDialog> createState() =>
      _QuantitySelectionDialogState();
}

class _QuantitySelectionDialogState extends State<QuantitySelectionDialog> {
  final TextEditingController _quantityController = TextEditingController();
  double _quantity = 1.0;
  double _calculatedPrice = 0.0;

  @override
  void initState() {
    super.initState();
    _quantityController.text = '1';
    _calculatedPrice = widget.product.price;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  bool get _isWeightBased {
    final type = widget.product.measurementType.toLowerCase();
    return type == 'kg' || type == 'gm';
  }

  String get _measurementUnit {
    return widget.product.measurementType.toLowerCase();
  }

  void _updateQuantity(String value) {
    if (value.isEmpty) {
      setState(() {
        _quantity = 0;
        _calculatedPrice = 0;
      });
      return;
    }

    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      return;
    }

    // Validate against stock
    if (parsed > widget.product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum available: ${widget.product.stock.toStringAsFixed(_isWeightBased ? 2 : 0)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 2),
        ),
      );
      _quantityController.text = widget.product.stock.toStringAsFixed(
        _isWeightBased ? 2 : 0,
      );
      setState(() {
        _quantity = widget.product.stock;
        _calculatedPrice = widget.product.stock * widget.product.price;
      });
      return;
    }

    setState(() {
      _quantity = parsed;
      _calculatedPrice = parsed * widget.product.price;
    });
  }

  void _increment() {
    final newValue = _quantity + (_isWeightBased ? 0.1 : 1);
    if (newValue > widget.product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum available: ${widget.product.stock.toStringAsFixed(_isWeightBased ? 2 : 0)}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    _quantityController.text = newValue.toStringAsFixed(_isWeightBased ? 1 : 0);
    _updateQuantity(_quantityController.text);
  }

  void _decrement() {
    if (_quantity <= (_isWeightBased ? 0.1 : 1)) return;
    final newValue = _quantity - (_isWeightBased ? 0.1 : 1);
    _quantityController.text = newValue.toStringAsFixed(_isWeightBased ? 1 : 0);
    _updateQuantity(_quantityController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product info
            Row(
              children: [
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
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${widget.product.price.toStringAsFixed(2)} per $_measurementUnit',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Available: ${widget.product.stock.toStringAsFixed(_isWeightBased ? 2 : 0)} $_measurementUnit',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Quantity input
            Text(
              'Quantity',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Decrement button
                IconButton.filled(
                  onPressed: _quantity <= (_isWeightBased ? 0.1 : 1)
                      ? null
                      : _decrement,
                  icon: const Icon(Icons.remove),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 12),
                // Quantity input
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: _isWeightBased,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(_isWeightBased ? r'^\d+\.?\d{0,2}' : r'^\d+'),
                      ),
                    ],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      suffixText: _measurementUnit,
                      suffixStyle: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.outline,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: _updateQuantity,
                  ),
                ),
                const SizedBox(width: 12),
                // Increment button
                IconButton.filled(
                  onPressed: _quantity >= widget.product.stock
                      ? null
                      : _increment,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
            if (_isWeightBased) ...[
              const SizedBox(height: 12),
              Obx(() {
                final scale = WeighingScaleService.instance;
                final scaleWeight = scale.currentWeight.value;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.scale_rounded, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Scale: ${scaleWeight.toStringAsFixed(3)} kg',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      if (scale.isStable.value)
                        const Text(
                          '(STABLE)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      const Spacer(),
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: scaleWeight > 0
                            ? () {
                                _quantityController.text = scaleWeight.toStringAsFixed(2);
                                _updateQuantity(_quantityController.text);
                              }
                            : null,
                        child: const Text('Capture Weight', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 24),
            // Total price
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    '₹${_calculatedPrice.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _quantity > 0 && _quantity <= widget.product.stock
                        ? () => Navigator.pop(context, _quantity)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Add to Cart'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
