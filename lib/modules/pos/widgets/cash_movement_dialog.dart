import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/hardware/printer_service.dart';
import '../controllers/shift_controller.dart';

/// Modal dialog for mid-shift drawer Cash In (change deposit) / Cash Out (petty cash payout)
class CashMovementDialog extends StatefulWidget {
  final String cashierName;

  const CashMovementDialog({
    super.key,
    required this.cashierName,
  });

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  String _movementType = 'cash_out'; // 'cash_in' or 'cash_out'
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _authorizerController = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  final List<String> _cashInPresets = [
    'Change Float Addition',
    'Denomination Exchange',
    'Customer Returned Loan',
    'Owner Deposit',
  ];

  final List<String> _cashOutPresets = [
    'Vendor Delivery Payment',
    'Shop Cleaning / Supplies',
    'Staff Tea / Refreshments',
    'Mid-day Safe Drop',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _pinController.dispose();
    _authorizerController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorText = 'Please enter a valid positive amount');
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorText = 'Please enter or select a reason for this drawer movement');
      return;
    }

    // Verify Manager PIN if required
    final printer = PrinterService.instance;
    if (printer.drawerRequiresPin.value) {
      if (_pinController.text.trim() != printer.managerPin.value) {
        setState(() => _errorText = 'Invalid Manager PIN. Authorization required.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    final authorizer = _authorizerController.text.trim().isNotEmpty
        ? _authorizerController.text.trim()
        : 'Manager';

    try {
      final success = await ShiftController.instance.recordCashMovement(
        type: _movementType,
        amount: amount,
        reason: reason,
        authorizedBy: authorizer,
      );

      if (success) {
        if (mounted) {
          Navigator.of(context).pop(true);
          final label = _movementType == 'cash_in' ? 'Cash In (Deposit)' : 'Cash Out (Payout)';
          Get.snackbar(
            'Drawer Movement Recorded',
            '$label of ₹${amount.toStringAsFixed(2)} processed.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: _movementType == 'cash_in' ? Colors.teal.shade800 : Colors.amber.shade900,
            colorText: Colors.white,
            duration: const Duration(seconds: 3),
          );
        }
      } else {
        setState(() {
          _submitting = false;
          _errorText = ShiftController.instance.error.value.isNotEmpty
              ? ShiftController.instance.error.value
              : 'Failed to record movement';
        });
      }
    } catch (e) {
      setState(() {
        _submitting = false;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = _movementType == 'cash_in' ? _cashInPresets : _cashOutPresets;
    final isCashIn = _movementType == 'cash_in';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
                      color: isCashIn ? Colors.teal.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isCashIn ? Icons.transit_enterexit : Icons.monetization_on,
                      color: isCashIn ? Colors.teal.shade700 : Colors.amber.shade900,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Drawer Petty Cash Movement',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Cashier: ${widget.cashierName}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),

              // Segmented selector: Cash In vs Cash Out
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCashIn ? Colors.teal.shade700 : Colors.grey.shade200,
                        foregroundColor: isCashIn ? Colors.white : Colors.black87,
                        elevation: isCashIn ? 2 : 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(() => _movementType = 'cash_in'),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Cash In (Deposit)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: !isCashIn ? Colors.red.shade700 : Colors.grey.shade200,
                        foregroundColor: !isCashIn ? Colors.white : Colors.black87,
                        elevation: !isCashIn ? 2 : 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(() => _movementType = 'cash_out'),
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      label: const Text('Cash Out (Payout)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              const Text('Amount (₹):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  hintText: '0.00',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              const Text('Reason / Description:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                decoration: InputDecoration(
                  hintText: isCashIn ? 'e.g. Added ₹500 change' : 'e.g. Paid vendor ₹250',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 8),

              // Reason chips
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: presets.map((preset) {
                  return ActionChip(
                    label: Text(preset, style: const TextStyle(fontSize: 11)),
                    onPressed: () => _reasonController.text = preset,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Manager PIN & Authorization
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Manager PIN:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'PIN',
                            prefixIcon: const Icon(Icons.lock_outline, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Authorized By:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _authorizerController,
                          decoration: InputDecoration(
                            hintText: 'Manager Name',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

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
                        child: Text(
                          _errorText!,
                          style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCashIn ? Colors.teal.shade700 : Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(_submitting ? 'Recording...' : 'Record & Kick Drawer'),
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
