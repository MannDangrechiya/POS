import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/hardware/cfd_service.dart';

/// Full-screen Customer Facing Display (CFD) for secondary monitor or customer tablet.
class CustomerFacingDisplayScreen extends StatelessWidget {
  const CustomerFacingDisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cfd = CfdService.instance;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Obx(() => Text(
              cfd.storeName.value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            )),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Simulate Welcome',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => cfd.resetToWelcome(),
          ),
          IconButton(
            tooltip: 'Close Screen',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Obx(() {
        switch (cfd.state.value) {
          case CfdScreenState.welcome:
            return _buildWelcomeView(context, colorScheme);
          case CfdScreenState.ringing:
            return _buildRingingView(context, cfd, colorScheme);
          case CfdScreenState.paying:
            return _buildPayingView(context, cfd, colorScheme);
          case CfdScreenState.completed:
            return _buildCompletedView(context, cfd, colorScheme);
        }
      }),
    );
  }

  Widget _buildWelcomeView(BuildContext context, ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_basket_rounded,
              size: 96,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Welcome to Fresh Fruit Mart',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Premium Quality Fruits & Wholesale Fresh Produce',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Next Customer Please',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRingingView(
    BuildContext context,
    CfdService cfd,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        // Left Column: Scanned items list
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Banner for last scanned item
              if (cfd.lastScannedItem.value.isNotEmpty)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: colorScheme.primary, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cfd.lastScannedItem.value,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      Text(
                        '₹${cfd.lastScannedPrice.value.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),

              // Items table
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cfd.displayItems.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final item = cfd.displayItems[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '₹${item.priceSnapshot.toStringAsFixed(2)} / ${item.product.measurementType.toLowerCase()}',
                                  style: TextStyle(
                                    color: colorScheme.outline,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${item.quantityOrWeight.toStringAsFixed(item.product.isWeightBased ? 2 : 0)} ${item.product.measurementType.toLowerCase()}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '₹${item.totalPrice.toStringAsFixed(2)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1),

        // Right Column: Summary & Total
        Expanded(
          flex: 4,
          child: Container(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cfd.customerName.value.isNotEmpty) ...[
                  Text(
                    'Customer: ${cfd.customerName.value}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Item Count: ${cfd.displayItems.length}',
                  style: TextStyle(color: colorScheme.outline, fontSize: 14),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'TOTAL AMOUNT',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '₹${cfd.grandTotal.value.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPayingView(
    BuildContext context,
    CfdService cfd,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Total Amount Due',
              style: TextStyle(fontSize: 18, color: colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Text(
              '₹${cfd.grandTotal.value.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            if (cfd.upiUri.value.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: cfd.upiUri.value,
                  version: QrVersions.auto,
                  size: 220.0,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Scan with Google Pay, PhonePe, or Paytm',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ] else if (cfd.paymentMethod.value.toLowerCase() == 'cash') ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cash Tendered:'),
                        Text(
                          '₹${cfd.cashTendered.value.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Change to Return:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '₹${cfd.changeReturned.value.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedView(
    BuildContext context,
    CfdService cfd,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 80,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Payment Successful!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thank you for shopping at Fresh Fruit Mart!',
            style: TextStyle(fontSize: 16),
          ),
          if (cfd.changeReturned.value > 0) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Text(
                'Please collect your change: ₹${cfd.changeReturned.value.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[900],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
