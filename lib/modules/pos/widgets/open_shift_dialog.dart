import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/shift_controller.dart';

/// Modal dialog prompting the cashier to declare starting drawer cash float.
class OpenShiftDialog extends StatefulWidget {
  final String shopId;
  final String cashierId;
  final String cashierName;

  const OpenShiftDialog({
    super.key,
    required this.shopId,
    required this.cashierId,
    required this.cashierName,
  });

  @override
  State<OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<OpenShiftDialog> {
  final TextEditingController _floatController = TextEditingController(text: '1000');
  final TextEditingController _notesController = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  final List<double> _quickPresets = [500, 1000, 2000, 5000];

  @override
  void dispose() {
    _floatController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_floatController.text.trim());
    if (amount == null || amount < 0) {
      setState(() => _errorText = 'Please enter a valid starting float amount');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final shift = await ShiftController.instance.openShift(
        shopId: widget.shopId,
        cashierId: widget.cashierId,
        cashierName: widget.cashierName,
        openingFloat: amount,
        notes: _notesController.text.trim(),
      );

      if (shift != null) {
        if (mounted) {
          Navigator.of(context).pop(true);
          Get.snackbar(
            'Shift Opened',
            'Drawer initialized with ₹${amount.toStringAsFixed(2)} opening float',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green.shade800,
            colorText: Colors.white,
            duration: const Duration(seconds: 3),
          );
        }
      } else {
        setState(() {
          _submitting = false;
          _errorText = ShiftController.instance.error.value.isNotEmpty
              ? ShiftController.instance.error.value
              : 'Failed to open shift';
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
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
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.point_of_sale, color: Colors.green.shade700, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Open Cashier Shift',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
              const Divider(height: 32),
              const Text(
                'Starting Drawer Float (Cash in Drawer):',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _floatController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  hintText: '0.00',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
              const SizedBox(height: 12),
              // Preset chips
              Wrap(
                spacing: 8,
                children: _quickPresets.map((preset) {
                  return ActionChip(
                    label: Text('+₹${preset.toInt()}'),
                    onPressed: () {
                      _floatController.text = preset.toStringAsFixed(0);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Shift Opening Notes (Optional):',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  hintText: 'e.g. Morning opening shift, received float from safe',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
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
                      backgroundColor: Colors.green.shade700,
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
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_submitting ? 'Opening...' : 'Start Shift & Pop Drawer'),
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
