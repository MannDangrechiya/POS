import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../data/models/shift_model.dart';
import '../controllers/shift_controller.dart';

/// Modal dialog for End-of-Shift Blind Drawer Count & Thermal Z-Report Reconciliation.
class CloseShiftDialog extends StatefulWidget {
  final String shopName;
  final String shopAddress;

  const CloseShiftDialog({
    super.key,
    this.shopName = 'Fruit POS Store',
    this.shopAddress = '',
  });

  @override
  State<CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<CloseShiftDialog> {
  // Step 1: Blind Count Entry | Step 2: Audit Results & Z-Report
  int _step = 1;

  final TextEditingController _totalCountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Optional denomination breakdown
  final Map<int, int> _denominations = {
    500: 0,
    200: 0,
    100: 0,
    50: 0,
    20: 0,
    10: 0,
    5: 0,
    1: 0,
  };
  bool _useDenominations = false;

  bool _submitting = false;
  String? _errorText;
  ShiftModel? _reconciledShift;

  @override
  void dispose() {
    _totalCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateFromDenominations() {
    double total = 0.0;
    _denominations.forEach((denom, count) {
      total += denom * count;
    });
    _totalCountController.text = total.toStringAsFixed(0);
    setState(() {});
  }

  Future<void> _submitBlindCount() async {
    final amount = double.tryParse(_totalCountController.text.trim());
    if (amount == null || amount < 0) {
      setState(() => _errorText = 'Please enter a valid cash count (₹0 or greater)');
      return;
    }

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final closedShift = await ShiftController.instance.closeShiftBlindCount(
        countedCash: amount,
        notes: _notesController.text.trim(),
        shopName: widget.shopName,
        shopAddress: widget.shopAddress,
      );

      if (closedShift != null) {
        setState(() {
          _submitting = false;
          _step = 2;
          _reconciledShift = closedShift;
        });
      } else {
        setState(() {
          _submitting = false;
          _errorText = ShiftController.instance.error.value.isNotEmpty
              ? ShiftController.instance.error.value
              : 'Failed to close shift';
        });
      }
    } catch (e) {
      setState(() {
        _submitting = false;
        _errorText = e.toString();
      });
    }
  }

  Future<void> _reprintZReport() async {
    if (_reconciledShift == null) return;
    await PrinterService.instance.printZReport(
      _reconciledShift!,
      shopName: widget.shopName,
      shopAddress: widget.shopAddress,
    );
    Get.snackbar(
      'Z-Report',
      'Sent to printer',
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.blueGrey.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: _step == 1 ? _buildBlindCountStep() : _buildAuditSummaryStep(),
        ),
      ),
    );
  }

  Widget _buildBlindCountStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.calculate, color: Colors.deepPurple.shade700, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'End Shift - Blind Drawer Count',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Count physical cash before system reveals totals',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 28),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Blind Count Audit Rule: Enter the exact physical cash amount present in the drawer. The system will then compare your count against sales and float movements.',
                  style: TextStyle(color: Colors.blue.shade900, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Actual Physical Cash Counted:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _useDenominations = !_useDenominations);
              },
              icon: Icon(_useDenominations ? Icons.keyboard : Icons.grid_view, size: 16),
              label: Text(_useDenominations ? 'Enter Total' : 'Breakdown By Notes'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (!_useDenominations)
          TextField(
            controller: _totalCountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              hintText: '0.00',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                ..._denominations.keys.map((denom) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text('₹$denom x', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onChanged: (val) {
                                final count = int.tryParse(val) ?? 0;
                                _denominations[denom] = count;
                                _updateFromDenominations();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: Text(
                            '= ₹${(_denominations[denom]! * denom).toStringAsFixed(0)}',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Calculated:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      '₹${_totalCountController.text.isEmpty ? '0' : _totalCountController.text}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                    ),
                  ],
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),
        const Text('Closing Notes / Remarks (Optional):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesController,
          decoration: InputDecoration(
            hintText: 'e.g. End of evening shift, all safe drops accounted for',
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
                  child: Text(_errorText!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
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
                backgroundColor: Colors.deepPurple.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _submitting ? null : _submitBlindCount,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.receipt_long),
              label: Text(_submitting ? 'Auditing & Printing...' : 'Reconcile & Close Shift'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAuditSummaryStep() {
    final shift = _reconciledShift!;
    final diff = shift.difference ?? 0.0;
    final isOverage = diff > 0.01;
    final isShortage = diff < -0.01;

    Color statusColor = Colors.green.shade700;
    String statusTitle = 'Drawer Balanced';
    IconData statusIcon = Icons.check_circle;

    if (isOverage) {
      statusColor = Colors.blue.shade700;
      statusTitle = 'Cash Overage (+₹${diff.toStringAsFixed(2)})';
      statusIcon = Icons.arrow_upward;
    } else if (isShortage) {
      statusColor = Colors.red.shade700;
      statusTitle = 'Cash Shortage (-₹${diff.abs().toStringAsFixed(2)})';
      statusIcon = Icons.warning_amber_rounded;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(statusIcon, color: statusColor, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusTitle,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                  const Text('Shift successfully closed & audited', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 28),

        // Reconciliation Table
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              _auditRow('Opening Float', '₹${shift.openingFloat.toStringAsFixed(2)}'),
              _auditRow('+ Cash Sales', '₹${shift.cashSales.toStringAsFixed(2)}'),
              _auditRow('+ Cash In (Float)', '₹${shift.cashInTotal.toStringAsFixed(2)}'),
              _auditRow('- Cash Out (Payouts)', '₹${shift.cashOutTotal.toStringAsFixed(2)}'),
              const Divider(height: 16),
              _auditRow('EXPECTED DRAWER CASH', '₹${shift.expectedCash.toStringAsFixed(2)}', bold: true),
              _auditRow('ACTUAL COUNTED CASH', '₹${(shift.actualCashCounted ?? 0.0).toStringAsFixed(2)}', bold: true),
              const Divider(height: 16),
              _auditRow('VARIANCE', '${diff >= 0 ? '+' : '-'}₹${diff.abs().toStringAsFixed(2)}', bold: true, color: statusColor),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Sales Breakdown Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _salesCol('Cash', '₹${shift.cashSales.toStringAsFixed(0)}'),
              _salesCol('UPI', '₹${shift.upiSales.toStringAsFixed(0)}'),
              _salesCol('Card', '₹${shift.cardSales.toStringAsFixed(0)}'),
              _salesCol('Gross Sales', '₹${shift.grossSales.toStringAsFixed(0)}', bold: true),
            ],
          ),
        ),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: _reprintZReport,
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Reprint Z-Report'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Done & Exit Shift'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _auditRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 14 : 13,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesCol(String label, String val, {bool bold = false}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.teal.shade900)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600, fontSize: 13, color: Colors.teal.shade900)),
      ],
    );
  }
}
