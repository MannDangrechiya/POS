import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/hardware/printer_service.dart';
import '../controllers/cart_controller.dart';

/// Modal dialog for applying item or cart discounts (% or Flat Rupee) with manager authorization.
class DiscountDialog extends StatefulWidget {
  final CartController cartController;

  const DiscountDialog({
    super.key,
    required this.cartController,
  });

  @override
  State<DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<DiscountDialog> {
  bool _isPercent = true;
  final TextEditingController _valController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  String? _errorText;

  final List<double> _percentPresets = [5, 10, 15, 20];
  final List<double> _flatPresets = [20, 50, 100, 200];

  final List<String> _reasonPresets = [
    'Regular Customer Goodwill',
    'Slightly Overripe / Clearance',
    'Bulk Order Discount',
    'Promotional Campaign',
    'Damaged Packaging',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.cartController.discountAmount.value > 0) {
      _valController.text = widget.cartController.discountAmount.value.toStringAsFixed(0);
      _reasonController.text = widget.cartController.discountReason.value;
      _isPercent = false;
    }
  }

  @override
  void dispose() {
    _valController.dispose();
    _reasonController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _applyDiscount() {
    final val = double.tryParse(_valController.text.trim());
    if (val == null || val <= 0) {
      setState(() => _errorText = 'Please enter a valid discount value');
      return;
    }

    final subtotal = widget.cartController.subtotal;
    if (subtotal <= 0) {
      setState(() => _errorText = 'Cart is empty. Cannot apply discount.');
      return;
    }

    // High discount threshold check: > 15% or > ₹200 requires Manager PIN
    final bool requiresPin = _isPercent ? val > 15 : val > 200;
    if (requiresPin) {
      final printer = PrinterService.instance;
      if (_pinController.text.trim() != printer.managerPin.value) {
        setState(() => _errorText = 'Discounts exceeding 15% / ₹200 require Manager PIN');
        return;
      }
    }

    final reason = _reasonController.text.trim();

    if (_isPercent) {
      widget.cartController.applyDiscountPercent(val, reason: reason);
    } else {
      widget.cartController.applyDiscountFlat(val, reason: reason);
    }

    Navigator.of(context).pop(true);
    Get.snackbar(
      'Discount Applied',
      'Saved ₹${widget.cartController.discountAmount.value.toStringAsFixed(2)} on this order',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.indigo.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  void _removeDiscount() {
    widget.cartController.clearDiscount();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.cartController.subtotal;
    final currentVal = double.tryParse(_valController.text.trim()) ?? 0.0;
    final bool isHighDiscount = _isPercent ? currentVal > 15 : currentVal > 200;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.discount_outlined, color: Colors.indigo.shade700, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Order Discount Engine',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Current Subtotal: ₹${subtotal.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),

              // Percent vs Flat Toggle
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPercent ? Colors.indigo.shade700 : Colors.grey.shade200,
                        foregroundColor: _isPercent ? Colors.white : Colors.black87,
                        elevation: _isPercent ? 2 : 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(() => _isPercent = true),
                      child: const Text('Percentage (%)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !_isPercent ? Colors.indigo.shade700 : Colors.grey.shade200,
                        foregroundColor: !_isPercent ? Colors.white : Colors.black87,
                        elevation: !_isPercent ? 2 : 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(() => _isPercent = false),
                      child: const Text('Flat Rupee (₹)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                _isPercent ? 'Discount Percentage (%):' : 'Discount Rupee Amount (₹):',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _valController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixText: _isPercent ? '% ' : '₹ ',
                  hintText: '0',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 10),

              // Preset chips
              Wrap(
                spacing: 8,
                children: (_isPercent ? _percentPresets : _flatPresets).map((preset) {
                  return ActionChip(
                    label: Text(_isPercent ? '${preset.toInt()}%' : '₹${preset.toInt()}'),
                    onPressed: () {
                      _valController.text = preset.toStringAsFixed(0);
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              const Text('Discount Reason:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                decoration: InputDecoration(
                  hintText: 'e.g. Regular Customer Discount',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _reasonPresets.map((r) {
                  return ActionChip(
                    label: Text(r, style: const TextStyle(fontSize: 11)),
                    onPressed: () => _reasonController.text = r,
                  );
                }).toList(),
              ),

              if (isHighDiscount) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Manager Authorization Required (>15% / >₹200)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pinController,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: 'Enter Manager PIN',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorText!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.cartController.discountAmount.value > 0)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                      onPressed: _removeDiscount,
                      child: const Text('Remove Discount'),
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _applyDiscount,
                    child: const Text('Apply Discount'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
