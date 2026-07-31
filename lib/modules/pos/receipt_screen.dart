import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/models/product_model.dart';
import '../../core/services/storage_service.dart';
import 'pos_home_screen.dart';
import '../../routing/guarded_navigator.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';

/// Order Success & Receipt Screen - Display order confirmation and receipt
class ReceiptScreen extends StatelessWidget {
  final String orderId;
  final String customerName;
  final String customerMobile;
  final double totalAmount;
  final String paymentMethod;

  const ReceiptScreen({
    super.key,
    required this.orderId,
    required this.customerName,
    required this.customerMobile,
    required this.totalAmount,
    required this.paymentMethod,
  });

  String _getPaymentMethodLabel() {
    switch (paymentMethod.toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'upi':
        return 'UPI / Online Payment';
      case 'card':
        return 'Card';
      default:
        return paymentMethod;
    }
  }

  Future<void> _downloadAndUploadReceipt(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    try {
      // Load order items with product names
      final itemsSnapshot = await FirebaseFirestore.instance
          .collection('order_items')
          .where('orderId', isEqualTo: orderId)
          .get();

      final items = <Map<String, dynamic>>[];

      for (final itemDoc in itemsSnapshot.docs) {
        final itemData = itemDoc.data();
        final productDoc = await FirebaseFirestore.instance
            .collection('products')
            .doc(itemData['productId'] as String)
            .get();

        final product = ProductModel.tryFromDocument(productDoc);
        if (product != null) {
          items.add({
            'product': product,
            'quantity':
                (itemData['quantityOrWeight'] as num?)?.toDouble() ?? 0.0,
            'price':
                (itemData['priceSnapshot'] as num?)?.toDouble() ?? 0.0,
            'total':
                (itemData['totalPrice'] as num?)?.toDouble() ?? 0.0,
          });
        }
      }

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Receipt',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text('Order ID: $orderId'),
                pw.Text('Customer: $customerName'),
                pw.Text('Mobile: $customerMobile'),
                pw.Text('Payment: ${_getPaymentMethodLabel()}'),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Items',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                if (items.isEmpty)
                  pw.Text('No items found')
                else
                  pw.Column(
                    children: items.map((item) {
                      final product =
                          item['product'] as ProductModel;
                      final quantity =
                          (item['quantity'] as num).toDouble();
                      final price =
                          (item['price'] as num).toDouble();
                      final total =
                          (item['total'] as num).toDouble();
                      return pw.Container(
                        margin:
                            const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Row(
                          mainAxisAlignment:
                              pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Expanded(
                              child: pw.Text(product.name),
                            ),
                            pw.Text(
                              '${quantity.toStringAsFixed(2)} ${product.measurementType.toLowerCase()} × ₹${price.toStringAsFixed(2)}',
                            ),
                            pw.SizedBox(width: 8),
                            pw.Text(
                              '₹${total.toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Amount',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '₹${totalAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();

      // Allow user to download/share the PDF locally
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'receipt_$orderId.pdf',
      );

      // Upload to Firebase Storage
      await StorageService.instance.uploadReceipt(
        orderId: orderId,
        pdfBytes: bytes,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt saved to cloud storage'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export receipt: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.receipt,
      child: _buildReceipt(context),
    );
  }

  Widget _buildReceipt(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Confirmed'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Success icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle,
                        size: 48,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Order Placed Successfully!',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Order ID: $orderId',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.outline,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Date & Time: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Receipt card
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Order items
                            Text(
                              'Order Items',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: () async {
                                final itemsSnapshot = await FirebaseFirestore.instance
                                    .collection('order_items')
                                    .where('orderId', isEqualTo: orderId)
                                    .get();

                                final items = <Map<String, dynamic>>[];
                                
                                for (final itemDoc in itemsSnapshot.docs) {
                                  final itemData = itemDoc.data();
                                  final productDoc = await FirebaseFirestore.instance
                                      .collection('products')
                                      .doc(itemData['productId'] as String)
                                      .get();
                                  
                                  final product =
                                      ProductModel.tryFromDocument(productDoc);
                                  if (product != null) {
                                    items.add({
                                      'product': product,
                                      'quantity': itemData['quantityOrWeight'] as double,
                                      'price': itemData['priceSnapshot'] as double,
                                      'total': itemData['totalPrice'] as double,
                                    });
                                  }
                                }
                                
                                return items;
                              }(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('No items found'),
                                  );
                                }

                                final orderItems = snapshot.data!;

                                return Column(
                                  children: orderItems.map((item) {
                                    final product = item['product'] as ProductModel;
                                    final quantity = item['quantity'] as double;
                                    final total = item['total'] as double;
                                    final price = item['price'] as double;
                                    final isWeightBased = product.measurementType
                                        .toLowerCase() == 'kg' ||
                                        product.measurementType.toLowerCase() == 'gm';

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  product.name,
                                                  style: theme.textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${quantity.toStringAsFixed(isWeightBased ? 2 : 0)} ${product.measurementType.toLowerCase()} × ₹${price.toStringAsFixed(2)}',
                                                  style: theme.textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                    color: colorScheme
                                                        .outline,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '₹${total.toStringAsFixed(2)}',
                                            style: theme.textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                            const Divider(height: 32),
                            // Customer info
                            _ReceiptInfoRow(
                              label: 'Customer',
                              value: customerName,
                            ),
                            const SizedBox(height: 8),
                            _ReceiptInfoRow(
                              label: 'Mobile',
                              value: customerMobile,
                            ),
                            const SizedBox(height: 8),
                            _ReceiptInfoRow(
                              label: 'Payment Method',
                              value: _getPaymentMethodLabel(),
                            ),
                            const Divider(height: 32),
                            // Total
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Amount',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '₹${totalAmount.toStringAsFixed(2)}',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Print/share options
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Direct print will be available in a future update',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.print),
                            label: const Text('Print'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _downloadAndUploadReceipt(context),
                            icon: const Icon(Icons.share),
                            label: const Text('Download PDF'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // New order button
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
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    GuardedNavigator.pushAndRemoveUntil(
                      context,
                      permission: ScreenPermission.posHome,
                      page: const PosHomeScreen(),
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('New Order'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptInfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.outline,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
