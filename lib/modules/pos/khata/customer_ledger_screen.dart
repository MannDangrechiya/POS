import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';

import '../../../data/models/customer_model.dart';
import '../../../data/models/credit_ledger_model.dart';
import '../../../core/hardware/printer_service.dart';
import '../controllers/shift_controller.dart';

/// Customer Credit Ledger (Khata / Udhar) Management Screen
/// Displays customers with outstanding credit balances, transaction history,
/// and enables partial or full settlement with thermal payment receipts.
class CustomerLedgerScreen extends StatefulWidget {
  final String shopId;

  const CustomerLedgerScreen({
    super.key,
    required this.shopId,
  });

  @override
  State<CustomerLedgerScreen> createState() => _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends State<CustomerLedgerScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _onlyOutstanding = true;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Khata / Credit Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search customer by name or 10-digit mobile...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Outstanding Due Only'),
                      selected: _onlyOutstanding,
                      onSelected: (val) => setState(() => _onlyOutstanding = val),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('All Customers'),
                      selected: !_onlyOutstanding,
                      onSelected: (val) => setState(() => _onlyOutstanding = !val),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Customer List Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('customers')
                  .where('shopId', isEqualTo: widget.shopId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading customers: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var customers = snapshot.data!.docs
                    .map((d) => CustomerModel.tryFromMap(d.data()))
                    .whereType<CustomerModel>()
                    .toList();

                if (_onlyOutstanding) {
                  customers = customers.where((c) => c.currentBalance > 0.05).toList();
                }

                if (_searchQuery.isNotEmpty) {
                  customers = customers.where((c) {
                    final nameMatch = c.name.toLowerCase().contains(_searchQuery);
                    final mobileMatch = c.mobile.contains(_searchQuery);
                    return nameMatch || mobileMatch;
                  }).toList();
                }

                // Sort by highest outstanding balance first
                customers.sort((a, b) => b.currentBalance.compareTo(a.currentBalance));

                if (customers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 64, color: colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          _onlyOutstanding ? 'No outstanding credit balances!' : 'No customers found.',
                          style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.outline),
                        ),
                      ],
                    ),
                  );
                }

                final totalOutstanding = customers.fold<double>(0.0, (acc, c) => acc + c.currentBalance);

                return Column(
                  children: [
                    // Summary Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      color: Colors.amber.withValues(alpha: 0.15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Outstanding Khata (${customers.length} accounts):',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '₹${totalOutstanding.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: customers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final customer = customers[index];
                          return _CustomerCreditCard(
                            customer: customer,
                            shopId: widget.shopId,
                            onSettle: () => _openSettlementDialog(context, customer),
                            onViewLedger: () => _openLedgerHistorySheet(context, customer),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openSettlementDialog(BuildContext context, CustomerModel customer) {
    showDialog(
      context: context,
      builder: (_) => _SettlementDialog(
        shopId: widget.shopId,
        customer: customer,
      ),
    );
  }

  void _openLedgerHistorySheet(BuildContext context, CustomerModel customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CustomerLedgerSheet(
        shopId: widget.shopId,
        customer: customer,
        onSettle: () {
          Navigator.pop(context);
          _openSettlementDialog(context, customer);
        },
      ),
    );
  }
}

class _CustomerCreditCard extends StatelessWidget {
  final CustomerModel customer;
  final String shopId;
  final VoidCallback onSettle;
  final VoidCallback onViewLedger;

  const _CustomerCreditCard({
    required this.customer,
    required this.shopId,
    required this.onSettle,
    required this.onViewLedger,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final availableCredit = (customer.creditLimit - customer.currentBalance).clamp(0.0, customer.creditLimit);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: customer.currentBalance > 0
              ? Colors.amber.withValues(alpha: 0.5)
              : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  child: Text(
                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                    style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        customer.mobile,
                        style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${customer.currentBalance.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: customer.currentBalance > 0 ? Colors.red[700] : Colors.green[700],
                      ),
                    ),
                    Text(
                      'Outstanding Due',
                      style: theme.textTheme.labelSmall?.copyWith(color: colorScheme.outline),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Credit Limit: ₹${customer.creditLimit.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Available: ₹${availableCredit.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewLedger,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('View Khata'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: customer.currentBalance > 0 ? onSettle : null,
                    icon: const Icon(Icons.payment, size: 18),
                    label: const Text('Settle Balance'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green[700],
                    ),
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

class _CustomerLedgerSheet extends StatelessWidget {
  final String shopId;
  final CustomerModel customer;
  final VoidCallback onSettle;

  const _CustomerLedgerSheet({
    required this.shopId,
    required this.customer,
    required this.onSettle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${customer.name} - Ledger',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Mobile: ${customer.mobile} | Current Due: ₹${customer.currentBalance.toStringAsFixed(2)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: customer.currentBalance > 0 ? onSettle : null,
                    child: const Text('Settle'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('credit_ledgers')
                    .where('shopId', isEqualTo: shopId)
                    .where('customerId', isEqualTo: customer.customerId)
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error loading ledger: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final entries = snapshot.data!.docs
                      .map((d) => CreditLedgerModel.tryFromMap(d.data()))
                      .whereType<CreditLedgerModel>()
                      .toList();

                  if (entries.isEmpty) {
                    return const Center(child: Text('No credit ledger transactions found.'));
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = entries[index];
                      final isDebit = item.isDebit;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isDebit
                              ? Colors.red.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          child: Icon(
                            isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                            color: isDebit ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(
                          item.description,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${item.createdAt.day}/${item.createdAt.month}/${item.createdAt.year} ${item.createdAt.hour}:${item.createdAt.minute.toString().padLeft(2, '0')}'
                          ' • Balance After: ₹${item.balanceAfter.toStringAsFixed(2)}',
                        ),
                        trailing: Text(
                          '${isDebit ? '+' : '-'}₹${item.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDebit ? Colors.red[700] : Colors.green[700],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettlementDialog extends StatefulWidget {
  final String shopId;
  final CustomerModel customer;

  const _SettlementDialog({
    required this.shopId,
    required this.customer,
  });

  @override
  State<_SettlementDialog> createState() => _SettlementDialogState();
}

class _SettlementDialogState extends State<_SettlementDialog> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedMethod = 'cash';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.customer.currentBalance.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _processSettlement() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (amount > widget.customer.currentBalance + 0.05) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Amount cannot exceed outstanding due of ₹${widget.customer.currentBalance.toStringAsFixed(2)}'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final activeShiftId = Get.isRegistered<ShiftController>()
          ? ShiftController.instance.activeShift.value?.shiftId
          : null;

      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('settleCustomerCredit');

      final result = await callable.call({
        'shopId': widget.shopId,
        'customerId': widget.customer.customerId,
        'amountPaid': amount,
        'paymentMethod': _selectedMethod,
        'shiftId': ?activeShiftId,
        'notes': _notesController.text.trim(),
      });

      if (result.data['success'] == true) {
        final ledgerId = result.data['ledgerId'] as String;
        final newBalance = (result.data['newBalance'] as num).toDouble();

        // Auto print thermal settlement receipt
        await PrinterService.instance.printCreditSettlementReceipt(
          receiptId: ledgerId,
          customerName: widget.customer.name,
          customerMobile: widget.customer.mobile,
          previousBalance: widget.customer.currentBalance,
          amountPaid: amount,
          remainingBalance: newBalance,
          paymentMethod: _selectedMethod,
        );

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment of ₹${amount.toStringAsFixed(2)} recorded. Receipt printed!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(result.data['error'] ?? 'Settlement failed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
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
    final totalDue = widget.customer.currentBalance;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Settle Khata Payment',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.customer.name} (${widget.customer.mobile})',
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
              ),
              const Divider(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Outstanding Due:'),
                    Text(
                      '₹${totalDue.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.red[800],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Payment Amount (₹)',
                  prefixIcon: Icon(Icons.currency_rupee),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Full Due'),
                    onPressed: () => _amountController.text = totalDue.toStringAsFixed(2),
                  ),
                  if (totalDue >= 500)
                    ActionChip(
                      label: const Text('₹500'),
                      onPressed: () => _amountController.text = '500.00',
                    ),
                  if (totalDue >= 1000)
                    ActionChip(
                      label: const Text('₹1000'),
                      onPressed: () => _amountController.text = '1000.00',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Payment Mode',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _methodChip('cash', '💵 Cash'),
                  const SizedBox(width: 8),
                  _methodChip('upi', '📱 UPI'),
                  const SizedBox(width: 8),
                  _methodChip('card', '💳 Card'),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / Reference (Optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isProcessing ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isProcessing ? null : _processSettlement,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Record Payment & Print'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodChip(String method, String label) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          if (val) setState(() => _selectedMethod = method);
        },
      ),
    );
  }
}
