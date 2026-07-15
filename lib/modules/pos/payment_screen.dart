import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import 'controllers/cart_controller.dart';
import 'receipt_screen.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';
import '../../data/models/user_model.dart';

/// Payment Selection Screen - Select payment method and complete order
class PaymentScreen extends StatefulWidget {
  final String customerName;
  final String customerMobile;

  const PaymentScreen({
    super.key,
    required this.customerName,
    required this.customerMobile,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String? _selectedPaymentMethod;
  bool _isProcessing = false;
  String? _shopId;
  String? _userId;

  // Requirement in Detail §32.2 "Enable/disable payment methods" — read from
  // the shop's settings (Settings screen writes these; see settings_screen.dart
  // _KnownSettingKeys). Default to enabled when unset so existing shops with
  // no settings configured behave exactly as before this feature existed.
  bool _cashEnabled = true;
  bool _upiEnabled = true;
  bool _cardEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadUserData(context);
    });
  }

  Future<void> _loadUserData(BuildContext pageContext) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (pageContext.mounted) {
          Navigator.of(pageContext).pushReplacementNamed('/login');
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final userData = UserModel.tryFromDocument(userDoc);
        if (userData == null) return;
        if (!mounted) return;
        setState(() {
          _shopId = userData.shopId;
          _userId = userData.userId;
        });
        await _loadPaymentMethodSettings(userData.shopId);
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e')),
        );
      }
    }
  }

  Future<void> _loadPaymentMethodSettings(String shopId) async {
    if (shopId.isEmpty) return;
    try {
      // Direct document reads by well-known ID (matches settings_screen.dart's
      // `_settingIdFor`) — avoids needing a composite index for a query.
      final db = FirebaseFirestore.instance.collection('settings');
      final results = await Future.wait([
        db.doc('shop_${shopId}_payment_cash_enabled').get(),
        db.doc('shop_${shopId}_payment_upi_enabled').get(),
        db.doc('shop_${shopId}_payment_card_enabled').get(),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0].exists) {
          _cashEnabled = results[0].data()?['value'] as bool? ?? true;
        }
        if (results[1].exists) {
          _upiEnabled = results[1].data()?['value'] as bool? ?? true;
        }
        if (results[2].exists) {
          _cardEnabled = results[2].data()?['value'] as bool? ?? true;
        }
      });
    } catch (_) {
      // Non-fatal: keep all payment methods enabled (existing behavior) if
      // settings can't be read for any reason. Expected in the common case:
      // Firestore evaluates security rules even for a .get() on a document
      // that doesn't exist yet (shop never configured these settings), which
      // surfaces as permission-denied rather than a clean "not found" — that
      // is normal here, not a rules bug, and the safe default (enabled) is
      // exactly what should happen until an Admin configures otherwise.
    }
  }

  Future<void> _confirmOrder(BuildContext pageContext) async {
    if (_selectedPaymentMethod == null) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text('Please select a payment method'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_shopId == null || _userId == null) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(
            content: Text('Unable to process order. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final cartController = Get.find<CartController>();

      if (cartController.isEmpty) {
        if (pageContext.mounted) {
          ScaffoldMessenger.of(pageContext).showSnackBar(
            const SnackBar(
              content: Text('Cart is empty'),
              backgroundColor: Colors.red,
            ),
          );
        }
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }

      // Step 1: Create or get customer (Employee create permitted by Firestore rules)
      final customerId = await _createOrGetCustomer();

      // Step 2: Snapshot cart data before the async call
      final totalAmount = cartController.totalAmount;
      final cartItems = List.from(cartController.items);

      // Step 3: Send full cart to confirmOrder Cloud Function.
      // The function creates the order, order_items, deducts stock, and
      // writes inventory_logs + audit_logs — all in ONE Firestore transaction.
      // The client does NOT pre-write any order document — ghost orders are impossible.
      final functions = FirebaseFunctions.instance;
      final confirmOrderFunction = functions.httpsCallable('confirmOrder');

      final result = await confirmOrderFunction.call({
        'customerId': customerId,
        'shopId': _shopId,
        'paymentMethod': _selectedPaymentMethod,
        'totalAmount': totalAmount,
        'items': cartItems
            .map((item) => {
                  'productId': item.product.productId,
                  'quantityOrWeight': item.quantityOrWeight,
                  'priceSnapshot': item.priceSnapshot,
                  'totalPrice': item.totalPrice,
                })
            .toList(),
      });

      if (result.data['success'] == true) {
        // Step 4: Cloud Function returns the newly-created orderId
        final orderId = result.data['orderId'] as String;

        if (pageContext.mounted) {
          // Clear cart after order is locked server-side
          cartController.clear();

          // Step 5: Navigate to ReceiptScreen using the returned orderId
          GuardedNavigator.pushReplacement(
            pageContext,
            permission: ScreenPermission.receipt,
            page: ReceiptScreen(
              orderId: orderId,
              customerName: widget.customerName,
              customerMobile: widget.customerMobile,
              totalAmount: totalAmount,
              paymentMethod: _selectedPaymentMethod!,
            ),
          );
        }
      } else {
        throw Exception(result.data['error'] ?? 'Failed to confirm order');
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text('Error processing order: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<String> _createOrGetCustomer() async {
    // Check if customer already exists by mobile number in this shop
    final existingCustomers = await FirebaseFirestore.instance
        .collection('customers')
        .where('shopId', isEqualTo: _shopId)
        .where('mobile', isEqualTo: widget.customerMobile)
        .limit(1)
        .get();

    if (existingCustomers.docs.isNotEmpty) {
      return existingCustomers.docs.first.id;
    }

    // Create new customer (Employee create is allowed by Firestore rules)
    final customerRef =
        FirebaseFirestore.instance.collection('customers').doc();

    await customerRef.set({
      'customerId': customerRef.id,
      'shopId': _shopId,
      'name': widget.customerName,
      'mobile': widget.customerMobile,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return customerRef.id;
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.payment,
      child: _buildPayment(context),
    );
  }

  Widget _buildPayment(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Customer info summary
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.customerName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.customerMobile,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Payment methods
                    Text(
                      'Select Payment Method',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_cashEnabled && !_upiEnabled && !_cardEnabled)
                      Card(
                        color: colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No payment methods are enabled for this shop. '
                            'Contact your Admin.',
                            style: TextStyle(color: colorScheme.onErrorContainer),
                          ),
                        ),
                      ),
                    if (_cashEnabled) ...[
                      _PaymentMethodCard(
                        icon: Icons.money,
                        title: 'Cash',
                        subtitle: 'Cash payment',
                        isSelected: _selectedPaymentMethod == 'cash',
                        onTap: () {
                          setState(() {
                            _selectedPaymentMethod = 'cash';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_upiEnabled) ...[
                      _PaymentMethodCard(
                        icon: Icons.account_balance_wallet,
                        title: 'UPI / Online Payment',
                        subtitle: 'UPI, PhonePe, Google Pay, etc.',
                        isSelected: _selectedPaymentMethod == 'upi',
                        onTap: () {
                          setState(() {
                            _selectedPaymentMethod = 'upi';
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_cardEnabled)
                      _PaymentMethodCard(
                        icon: Icons.credit_card,
                        title: 'Card',
                        subtitle: 'Debit or Credit Card',
                        isSelected: _selectedPaymentMethod == 'card',
                        onTap: () {
                          setState(() {
                            _selectedPaymentMethod = 'card';
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            // Order summary and confirm button
            Container(
              padding: const EdgeInsets.all(24),
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
                  Obx(() {
                    final cartController = Get.find<CartController>();
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Amount',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
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
                    );
                  }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isProcessing ? null : () => _confirmOrder(context),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Confirm Order',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? colorScheme.primary
              : colorScheme.outline.withValues(alpha: 0.2),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
