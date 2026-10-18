import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controllers/cart_controller.dart';
import '../controllers/shift_controller.dart';
import '../receipt_screen.dart';
import '../../../routing/guarded_navigator.dart';
import '../../../routing/screen_permission.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/cfd_service.dart';
import '../../../core/hardware/terminal_service.dart';
import '../../../data/models/customer_model.dart';
import '../../../core/offline/offline_order_queue.dart';

/// Fast Payment & Order Confirmation Dialog
/// Enables in-place rapid checkout with Cash change calculator,
/// dynamic UPI QR code, and customer auto-lookup without leaving the billing screen.
class FastPaymentDialog extends StatefulWidget {
  final String shopId;
  final String initialPaymentMethod;

  const FastPaymentDialog({
    super.key,
    required this.shopId,
    this.initialPaymentMethod = 'cash',
  });

  static Future<void> show(
    BuildContext context, {
    required String shopId,
    String initialPaymentMethod = 'cash',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => FastPaymentDialog(
        shopId: shopId,
        initialPaymentMethod: initialPaymentMethod,
      ),
    );
  }

  @override
  State<FastPaymentDialog> createState() => _FastPaymentDialogState();
}

class _FastPaymentDialogState extends State<FastPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _nameController = TextEditingController();
  final _cashTenderedController = TextEditingController();
  final _cardRefController = TextEditingController();

  late String _selectedMethod;
  bool _isProcessing = false;
  bool _isLookingUpCustomer = false;
  CustomerModel? _foundCustomer;
  double _cashTendered = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.initialPaymentMethod;

    final cartController = Get.find<CartController>();
    if (cartController.customerMobile.value.isNotEmpty) {
      _mobileController.text = cartController.customerMobile.value;
      _lookupCustomerByMobile(cartController.customerMobile.value);
    }
    if (cartController.customerName.value.isNotEmpty) {
      _nameController.text = cartController.customerName.value;
    }

    _cashTendered = cartController.totalAmount;
    _cashTenderedController.text = _cashTendered.toStringAsFixed(2);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCfdPaymentState();
    });
  }

  void _syncCfdPaymentState() {
    final cartController = Get.find<CartController>();
    final upiUri = _buildDynamicUpiUri(cartController.totalAmount);
    CfdService.instance.showPaymentScreen(
      total: cartController.totalAmount,
      upi: upiUri,
      method: _selectedMethod,
      tendered: _cashTendered,
      change: _cashTendered - cartController.totalAmount,
    );
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _nameController.dispose();
    _cashTenderedController.dispose();
    _cardRefController.dispose();
    super.dispose();
  }

  Future<void> _lookupCustomerByMobile(String mobile) async {
    final cleaned = mobile.replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.length != 10) return;

    setState(() => _isLookingUpCustomer = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('customers')
          .where('shopId', isEqualTo: widget.shopId)
          .where('mobile', isEqualTo: cleaned)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty && mounted) {
        final data = snap.docs.first.data();
        _foundCustomer = CustomerModel.tryFromMap(data);
        final name = data['name'] as String? ?? '';
        if (name.isNotEmpty && _nameController.text.trim().isEmpty) {
          _nameController.text = name;
          final cartController = Get.find<CartController>();
          cartController.setCustomer(name, cleaned);
        }
      } else {
        _foundCustomer = null;
      }
    } catch (_) {
      // Non-fatal lookup failure
    } finally {
      if (mounted) {
        setState(() => _isLookingUpCustomer = false);
      }
    }
  }

  Future<String> _createOrGetCustomer(String mobile, String name) async {
    final existingCustomers = await FirebaseFirestore.instance
        .collection('customers')
        .where('shopId', isEqualTo: widget.shopId)
        .where('mobile', isEqualTo: mobile)
        .limit(1)
        .get();

    if (existingCustomers.docs.isNotEmpty) {
      return existingCustomers.docs.first.id;
    }

    final customerRef =
        FirebaseFirestore.instance.collection('customers').doc();

    await customerRef.set({
      'customerId': customerRef.id,
      'shopId': widget.shopId,
      'name': name,
      'mobile': mobile,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return customerRef.id;
  }

  Future<void> _completeCheckout() async {
    if (!_formKey.currentState!.validate()) return;

    final cartController = Get.find<CartController>();
    if (cartController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
      return;
    }

    final totalAmount = cartController.totalAmount;
    if (_selectedMethod == 'cash' && _cashTendered < totalAmount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cash received (₹${_cashTendered.toStringAsFixed(2)}) is less than total amount (₹${totalAmount.toStringAsFixed(2)})',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedMethod == 'credit' && _foundCustomer != null) {
      if (_foundCustomer!.currentBalance + totalAmount > _foundCustomer!.creditLimit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Credit limit exceeded! Due: ₹${_foundCustomer!.currentBalance.toStringAsFixed(2)}, Limit: ₹${_foundCustomer!.creditLimit.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isProcessing = true);

    final customerMobile = _mobileController.text.trim();
    final customerName = _nameController.text.trim();
    final cartItems = List.from(cartController.items);
    Map<String, dynamic> payload = {};

    try {
      // 1. Create or retrieve customer
      final customerId = await _createOrGetCustomer(customerMobile, customerName);

      // 2. Build payload
      final activeShiftId = Get.isRegistered<ShiftController>()
          ? ShiftController.instance.activeShift.value?.shiftId
          : null;
      final termId = Get.isRegistered<TerminalService>()
          ? TerminalService.instance.terminalId.value
          : 'REG-01';

      payload = <String, dynamic>{
        'customerId': customerId,
        'shopId': widget.shopId,
        'paymentMethod': _selectedMethod,
        'totalAmount': totalAmount,
        'discountAmount': cartController.discountAmount.value,
        'taxAmount': cartController.taxAmount,
        'taxRatePercent': cartController.taxRatePercent.value,
        'terminalId': termId,
        'items': cartItems
            .map((item) => {
                  'productId': item.product.productId,
                  'quantityOrWeight': item.quantityOrWeight,
                  'priceSnapshot': item.priceSnapshot,
                  'totalPrice': item.totalPrice,
                })
            .toList(),
      };
      if (activeShiftId != null) {
        payload['shiftId'] = activeShiftId;
      }

      // 3. Call confirmOrder Cloud Function
      final functions = FirebaseFunctions.instance;
      final confirmOrderCallable = functions.httpsCallable('confirmOrder');
      final result = await confirmOrderCallable.call(payload);

      if (result.data['success'] == true) {
        final orderId = result.data['orderId'] as String;

        // Auto-kick cash drawer on cash transactions
        if (_selectedMethod.toLowerCase() == 'cash') {
          PrinterService.instance.kickCashDrawer();
        }

        // Notify CFD of success
        CfdService.instance.showCompletedScreen(
          orderId: orderId,
          change: _selectedMethod.toLowerCase() == 'cash'
              ? (_cashTendered - totalAmount)
              : 0.0,
        );

        // Clear cart
        cartController.clear();

        if (!mounted) return;
        Navigator.pop(context); // Close payment dialog

        // Show receipt view or print
        GuardedNavigator.push(
          context,
          permission: ScreenPermission.receipt,
          page: ReceiptScreen(
            orderId: orderId,
            customerName: customerName,
            customerMobile: customerMobile,
            totalAmount: totalAmount,
            paymentMethod: _selectedMethod,
          ),
        );
      } else {
        throw Exception(result.data['error'] ?? 'Order confirmation failed');
      }
    } catch (e) {
      // Offline fallback: Queue locally if internet down or Cloud Function unreachable
      final isNetwork = e.toString().contains('network') ||
          e.toString().contains('unavailable') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('deadline-exceeded');

      if (isNetwork && payload.isNotEmpty) {
        try {
          final receiptItems = cartItems
              .map((item) => ReceiptItemData(
                    name: item.product.name,
                    quantity: item.quantityOrWeight,
                    unit: item.product.measurementType,
                    price: item.priceSnapshot,
                    total: item.totalPrice,
                  ))
              .toList();

          final offlineId = await OfflineOrderQueue.instance.queueOrder(
            payload,
            customerName: customerName,
            customerMobile: customerMobile,
            totalAmount: totalAmount,
            paymentMethod: _selectedMethod,
            receiptItems: receiptItems,
          );

          cartController.clear();
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Offline: Order $offlineId saved locally. Receipt printed!'),
                backgroundColor: Colors.orange[800],
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  String _buildDynamicUpiUri(double amount) {
    // Standard UPI URI format accepted by PhonePe, GooglePay, Paytm, etc.
    final shopHandle = widget.shopId.length > 8
        ? widget.shopId.substring(0, 8)
        : widget.shopId;
    final pa = 'pos.$shopHandle@upi';
    final pn = 'Fruit POS';
    final am = amount.toStringAsFixed(2);
    final tr = 'TXN${DateTime.now().millisecondsSinceEpoch}';
    return 'upi://pay?pa=$pa&pn=$pn&am=$am&cu=INR&tr=$tr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cartController = Get.find<CartController>();
    final totalAmount = cartController.totalAmount;
    final changeToReturn = _cashTendered - totalAmount;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.point_of_sale,
                        color: colorScheme.primary, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      'Fast Checkout',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: _isProcessing ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(height: 24),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Customer Details Section
                        Text(
                          'Customer Details (Mandatory)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: TextFormField(
                                controller: _mobileController,
                                decoration: InputDecoration(
                                  labelText: 'Mobile Number',
                                  prefixIcon: const Icon(Icons.phone),
                                  suffixIcon: _isLookingUpCustomer
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : null,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                onChanged: (val) {
                                  if (val.length == 10) {
                                    _lookupCustomerByMobile(val);
                                  }
                                },
                                validator: (val) {
                                  if (val == null || val.trim().length != 10) {
                                    return 'Valid 10-digit mobile required';
                                  }
                                  if (!RegExp(r'^[6-9]').hasMatch(val)) {
                                    return 'Must start with 6-9';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 5,
                              child: TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Customer Name',
                                  prefixIcon: Icon(Icons.person),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                textCapitalization: TextCapitalization.words,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Name required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Total Payable Banner
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Payable Total (${cartController.itemCount} items)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '₹${totalAmount.toStringAsFixed(2)}',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Payment Method Selector Tabs
                        Text(
                          'Payment Method',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildMethodChip('cash', '💵 Cash', colorScheme),
                            const SizedBox(width: 6),
                            _buildMethodChip('upi', '📱 UPI', colorScheme),
                            const SizedBox(width: 6),
                            _buildMethodChip('card', '💳 Card', colorScheme),
                            const SizedBox(width: 6),
                            _buildMethodChip('credit', '📒 Khata', colorScheme),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Method Specific Views
                        if (_selectedMethod == 'cash') ...[
                          // Cash Tendered & Quick Calculator
                          TextFormField(
                            controller: _cashTenderedController,
                            decoration: const InputDecoration(
                              labelText: 'Cash Received from Customer (₹)',
                              prefixIcon: Icon(Icons.payments_outlined),
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onChanged: (val) {
                              setState(() {
                                _cashTendered = double.tryParse(val) ?? 0.0;
                              });
                            },
                          ),
                          const SizedBox(height: 10),
                          // Quick Cash Chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ActionChip(
                                label: Text(
                                    'Exact (₹${totalAmount.toStringAsFixed(0)})'),
                                onPressed: () {
                                  setState(() {
                                    _cashTendered = totalAmount;
                                    _cashTenderedController.text =
                                        totalAmount.toStringAsFixed(2);
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('₹100'),
                                onPressed: () => _setTenderAmount(100),
                              ),
                              ActionChip(
                                label: const Text('₹200'),
                                onPressed: () => _setTenderAmount(200),
                              ),
                              ActionChip(
                                label: const Text('₹500'),
                                onPressed: () => _setTenderAmount(500),
                              ),
                              ActionChip(
                                label: const Text('₹2000'),
                                onPressed: () => _setTenderAmount(2000),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Change Calculation Indicator
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: changeToReturn >= 0
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: changeToReturn >= 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  changeToReturn >= 0
                                      ? 'Change to Return:'
                                      : 'Remaining to Collect:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: changeToReturn >= 0
                                        ? Colors.green[800]
                                        : Colors.red[800],
                                  ),
                                ),
                                Text(
                                  '₹${changeToReturn.abs().toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 22,
                                    color: changeToReturn >= 0
                                        ? Colors.green[900]
                                        : Colors.red[900],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_selectedMethod == 'upi') ...[
                          // Dynamic UPI QR View
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colorScheme.outlineVariant),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  width: 170,
                                  height: 170,
                                  child: QrImageView(
                                    data: _buildDynamicUpiUri(totalAmount),
                                    version: QrVersions.auto,
                                    size: 170.0,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Scan with Google Pay, PhonePe, Paytm, or BHIM',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Exact Amount: ₹${totalAmount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_selectedMethod == 'card') ...[
                          // Card Terminal View
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colorScheme.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.credit_card, size: 28),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Card POS Terminal',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Swipe, tap, or insert customer card into EDC terminal for ₹${totalAmount.toStringAsFixed(2)}.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _cardRefController,
                                  decoration: const InputDecoration(
                                    labelText: 'Approval / Auth Code (Optional)',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_selectedMethod == 'credit') ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: (_foundCustomer != null &&
                                        (_foundCustomer!.currentBalance + totalAmount) > _foundCustomer!.creditLimit)
                                    ? Colors.red
                                    : colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.menu_book, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Customer Credit / Khata (Pay Later)',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (_foundCustomer == null)
                                  const Text(
                                    'Customer will be registered with standard credit limit (₹10,000.00).',
                                  )
                                else ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Credit Limit:'),
                                      Text(
                                        '₹${_foundCustomer!.creditLimit.toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Current Due:'),
                                      Text(
                                        '₹${_foundCustomer!.currentBalance.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Available Credit:'),
                                      Text(
                                        '₹${(_foundCustomer!.creditLimit - _foundCustomer!.currentBalance).clamp(0.0, _foundCustomer!.creditLimit).toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Balance After This Sale:'),
                                      Text(
                                        '₹${(_foundCustomer!.currentBalance + totalAmount).toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: (_foundCustomer!.currentBalance + totalAmount > _foundCustomer!.creditLimit)
                                              ? Colors.red
                                              : Colors.blue[800],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_foundCustomer!.currentBalance + totalAmount > _foundCustomer!.creditLimit) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      '⚠️ Order exceeds available credit limit!',
                                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                // Confirm Order Button
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isProcessing ? null : _completeCheckout,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _isProcessing
                          ? 'Confirming Order...'
                          : 'Complete Order (₹${totalAmount.toStringAsFixed(2)})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setTenderAmount(double amount) {
    setState(() {
      _cashTendered = amount;
      _cashTenderedController.text = amount.toStringAsFixed(2);
    });
  }

  Widget _buildMethodChip(String method, String label, ColorScheme colorScheme) {
    final isSelected = _selectedMethod == method;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedMethod = method),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
