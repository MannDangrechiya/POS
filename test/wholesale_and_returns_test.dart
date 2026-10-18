import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_system/data/models/product_model.dart';
import 'package:pos_system/data/models/refund_model.dart';
import 'package:pos_system/data/models/customer_model.dart';
import 'package:pos_system/data/models/credit_ledger_model.dart';
import 'package:pos_system/modules/pos/controllers/cart_controller.dart';
import 'package:pos_system/core/hardware/printer_service.dart';
import 'package:pos_system/core/offline/offline_order_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
  });

  tearDown(() {
    Get.reset();
  });

  group('Wholesale Tier Pricing Tests', () {
    test('PriceTier resolves correct unit price based on purchased quantity', () {
      final productWithTiers = ProductModel(
        productId: 'prod_mango_01',
        shopId: 'shop_001',
        name: 'Alphonso Mango',
        price: 100.0, // Base retail price
        measurementType: 'kg',
        stock: 500.0,
        status: 'Active',
        createdAt: DateTime.now(),
        tierPricing: const [
          PriceTier(minQuantity: 10.0, unitPrice: 85.0),  // 10kg+ @ ₹85/kg
          PriceTier(minQuantity: 50.0, unitPrice: 75.0),  // 50kg+ @ ₹75/kg
          PriceTier(minQuantity: 100.0, unitPrice: 65.0), // 100kg+ @ ₹65/kg
        ],
      );

      // Quantities below first tier use base retail price
      expect(productWithTiers.getPriceForQuantity(1.0), 100.0);
      expect(productWithTiers.getPriceForQuantity(5.5), 100.0);
      expect(productWithTiers.getPriceForQuantity(9.99), 100.0);

      // 10kg to 49.9kg uses Tier 1 (₹85.0)
      expect(productWithTiers.getPriceForQuantity(10.0), 85.0);
      expect(productWithTiers.getPriceForQuantity(25.0), 85.0);
      expect(productWithTiers.getPriceForQuantity(49.9), 85.0);

      // 50kg to 99.9kg uses Tier 2 (₹75.0)
      expect(productWithTiers.getPriceForQuantity(50.0), 75.0);
      expect(productWithTiers.getPriceForQuantity(75.0), 75.0);

      // 100kg+ uses Tier 3 (₹65.0)
      expect(productWithTiers.getPriceForQuantity(100.0), 65.0);
      expect(productWithTiers.getPriceForQuantity(250.0), 65.0);
    });

    test('Products without tiers return base retail price for any volume', () {
      final basicProduct = ProductModel(
        productId: 'prod_apple_01',
        shopId: 'shop_001',
        name: 'Shimla Apple',
        price: 150.0,
        measurementType: 'kg',
        stock: 100.0,
        status: 'Active',
        createdAt: DateTime.now(),
      );

      expect(basicProduct.getPriceForQuantity(1.0), 150.0);
      expect(basicProduct.getPriceForQuantity(20.0), 150.0);
      expect(basicProduct.getPriceForQuantity(100.0), 150.0);
    });

    test('CartController dynamically applies wholesale tier price as volume increases', () {
      final cart = Get.put(CartController());

      final wholesaleOrange = ProductModel(
        productId: 'prod_orange_01',
        shopId: 'shop_001',
        name: 'Nagpur Orange',
        price: 80.0, // Retail price
        measurementType: 'kg',
        stock: 200.0,
        status: 'Active',
        createdAt: DateTime.now(),
        tierPricing: const [
          PriceTier(minQuantity: 10.0, unitPrice: 65.0),
          PriceTier(minQuantity: 30.0, unitPrice: 55.0),
        ],
      );

      // Add 2kg at retail
      cart.addItem(wholesaleOrange, 2.0);
      expect(cart.items.first.priceSnapshot, 80.0);
      expect(cart.totalAmount, 160.0);

      // Update quantity to 15kg (crosses Tier 1 threshold)
      cart.updateQuantity(wholesaleOrange.productId, 15.0);
      expect(cart.items.first.priceSnapshot, 65.0);
      // 15kg * ₹65/kg = ₹975.0
      expect(cart.totalAmount, 975.0);

      // Update quantity to 40kg (crosses Tier 2 threshold)
      cart.updateQuantity(wholesaleOrange.productId, 40.0);
      expect(cart.items.first.priceSnapshot, 55.0);
      // 40kg * ₹55/kg = ₹2200.0
      expect(cart.totalAmount, 2200.0);

      // Reduce back to 5kg (reverts to retail rate)
      cart.updateQuantity(wholesaleOrange.productId, 5.0);
      expect(cart.items.first.priceSnapshot, 80.0);
      expect(cart.totalAmount, 400.0);
    });

    test('PriceTier serialization toMap and fromMap works seamlessly', () {
      const tier = PriceTier(minQuantity: 20.0, unitPrice: 45.5);
      final map = tier.toMap();

      expect(map['minQuantity'], 20.0);
      expect(map['unitPrice'], 45.5);

      final deserialized = PriceTier.fromMap(map);
      expect(deserialized.minQuantity, 20.0);
      expect(deserialized.unitPrice, 45.5);
    });
  });

  group('Itemized Returns & Refunds Tests', () {
    test('RefundModel and RefundItem serialization works correctly', () {
      final refundItem1 = RefundItem(
        productId: 'prod_001',
        productName: 'Papaya',
        quantityReturned: 2.0,
        unitPrice: 50.0,
        refundAmount: 100.0,
        disposition: 'restock',
        reason: 'Customer returned sealed box',
      );

      final refundItem2 = RefundItem(
        productId: 'prod_002',
        productName: 'Banana',
        quantityReturned: 3.0,
        unitPrice: 40.0,
        refundAmount: 120.0,
        disposition: 'damaged',
        reason: 'Overripe / spoiled',
      );

      final refund = RefundModel(
        refundId: 'ref_123',
        shopId: 'shop_001',
        orderId: 'ord_999',
        customerId: 'cust_01',
        customerName: 'Anil Kumar',
        employeeId: 'emp_01',
        employeeName: 'Ramesh',
        shiftId: 'shift_01',
        items: [refundItem1, refundItem2],
        totalRefundAmount: 220.0,
        refundMethod: 'cash',
        reason: 'Damaged fruit exchange',
        createdAt: DateTime(2026, 10, 18, 14, 30),
      );

      expect(refund.totalRefundAmount, 220.0);
      expect(refund.items.length, 2);
      expect(refund.items[0].disposition, 'restock');
      expect(refund.items[1].disposition, 'damaged');

      final map = refund.toMap();
      expect(map['refundId'], 'ref_123');
      expect(map['totalRefundAmount'], 220.0);
      expect((map['items'] as List).length, 2);

      final restored = RefundModel.fromMap(map);
      expect(restored.refundId, 'ref_123');
      expect(restored.totalRefundAmount, 220.0);
      expect(restored.items[0].productName, 'Papaya');
      expect(restored.items[1].disposition, 'damaged');
    });

    test('PrinterService generates thermal refund ticket preview and text', () async {
      final printer = Get.put(PrinterService());
      printer.connectionType.value = PrinterConnectionType.virtual;

      final refund = RefundModel(
        refundId: 'ref_samp_789',
        shopId: 'shop_001',
        orderId: 'ord_orig_456',
        customerId: 'cust_01',
        customerName: 'Suresh Patel',
        employeeId: 'emp_01',
        items: [
          const RefundItem(
            productId: 'p1',
            productName: 'Fresh Strawberries',
            quantityReturned: 2.0,
            unitPrice: 120.0,
            refundAmount: 240.0,
            disposition: 'restock',
          ),
          const RefundItem(
            productId: 'p2',
            productName: 'Pomegranate',
            quantityReturned: 1.0,
            unitPrice: 180.0,
            refundAmount: 180.0,
            disposition: 'damaged',
          ),
        ],
        totalRefundAmount: 420.0,
        refundMethod: 'cash',
        reason: 'Customer return',
        createdAt: DateTime.now(),
      );

      final ok = await printer.printRefundTicket(refund, shopName: 'Organic Fruit Market');
      expect(ok, true);

      final preview = printer.lastReceiptText.value;
      expect(preview.contains('RETURN & REFUND VOUCHER'), true);
      expect(preview.contains('ref_samp_789'), true);
      expect(preview.contains('420.00'), true);
      expect(preview.contains('RESTOCK'), true);
      expect(preview.contains('DAMAGED'), true);
    });
  });

  group('Customer Khata / Credit Ledger Tests', () {
    test('CustomerModel parses creditLimit and currentBalance with robust defaults', () {
      final mapWithCredit = {
        'customerId': 'c_1',
        'shopId': 's_1',
        'name': 'Ganesh Traders',
        'mobile': '9876543210',
        'creditLimit': 25000.0,
        'currentBalance': 8500.0,
        'createdAt': DateTime(2026, 1, 1),
      };

      final customer = CustomerModel.fromMap(mapWithCredit);
      expect(customer.creditLimit, 25000.0);
      expect(customer.currentBalance, 8500.0);

      // Verify defaults when fields are absent (legacy records)
      final legacyMap = {
        'customerId': 'c_2',
        'shopId': 's_1',
        'name': 'Walk-in Regular',
        'mobile': '9123456780',
        'createdAt': DateTime(2026, 1, 1),
      };

      final legacyCustomer = CustomerModel.fromMap(legacyMap);
      expect(legacyCustomer.creditLimit, 10000.0);
      expect(legacyCustomer.currentBalance, 0.0);
    });

    test('CreditLedgerModel identifies debits and credits correctly', () {
      final debitEntry = CreditLedgerModel(
        ledgerId: 'led_1',
        customerId: 'cust_01',
        shopId: 'shop_001',
        orderId: 'ord_101',
        type: 'debit',
        amount: 1500.0,
        balanceAfter: 4500.0,
        description: 'Order purchase on credit',
        createdBy: 'user_01',
        createdAt: DateTime.now(),
      );

      expect(debitEntry.isDebit, true);
      expect(debitEntry.isCredit, false);

      final creditEntry = CreditLedgerModel(
        ledgerId: 'led_2',
        customerId: 'cust_01',
        shopId: 'shop_001',
        type: 'credit',
        amount: 2000.0,
        balanceAfter: 2500.0,
        description: 'Weekly settlement payment (CASH)',
        paymentMethod: 'cash',
        createdBy: 'user_01',
        createdAt: DateTime.now(),
      );

      expect(creditEntry.isCredit, true);
      expect(creditEntry.isDebit, false);

      final map = creditEntry.toMap();
      expect(map['type'], 'credit');
      expect(map['paymentMethod'], 'cash');
      expect(map['amount'], 2000.0);
    });

    test('Credit limit check validates available balance accurately', () {
      final customer = CustomerModel(
        customerId: 'c_vip',
        shopId: 's_1',
        name: 'Kisan Wholesale',
        mobile: '9988776655',
        creditLimit: 15000.0,
        currentBalance: 12000.0,
        createdAt: DateTime.now(),
      );

      final availableCredit = customer.creditLimit - customer.currentBalance;
      expect(availableCredit, 3000.0);

      // Sale of ₹2,500 is within limit
      expect(customer.currentBalance + 2500.0 <= customer.creditLimit, true);

      // Sale of ₹3,500 exceeds limit
      expect(customer.currentBalance + 3500.0 <= customer.creditLimit, false);
    });

    test('PrinterService generates thermal credit settlement receipt', () async {
      final printer = Get.put(PrinterService());
      printer.connectionType.value = PrinterConnectionType.virtual;

      final ok = await printer.printCreditSettlementReceipt(
        receiptId: 'led_settle_555',
        customerName: 'Kisan Wholesale',
        customerMobile: '9988776655',
        previousBalance: 12000.0,
        amountPaid: 5000.0,
        remainingBalance: 7000.0,
        paymentMethod: 'cash',
        shopName: 'Central Fruit Depot',
      );

      expect(ok, true);
      final preview = printer.lastReceiptText.value;
      expect(preview.contains('KHATA PAYMENT RECEIPT'), true);
      expect(preview.contains('Kisan Wholesale'), true);
      expect(preview.contains('12000.00'), true);
      expect(preview.contains('5000.00'), true);
      expect(preview.contains('7000.00'), true);
    });
  });

  group('Offline Order Queue Tests', () {
    test('QueuedOrder serializes and deserializes payloads reliably', () {
      final payload = {
        'shopId': 'shop_001',
        'customerId': 'cust_01',
        'totalAmount': 850.0,
        'paymentMethod': 'cash',
        'items': [
          {'productId': 'p1', 'quantityOrWeight': 5.0, 'totalPrice': 850.0}
        ],
      };

      final order = QueuedOrder(
        offlineOrderId: 'OFFLINE_12345_6789',
        payload: payload,
        queuedAt: DateTime.now(),
        retryAttempts: 2,
        lastError: 'SocketException: Connection refused',
      );

      final map = order.toMap();
      expect(map['offlineOrderId'], 'OFFLINE_12345_6789');
      expect(map['retryAttempts'], 2);

      final restored = QueuedOrder.fromMap(map);
      expect(restored.offlineOrderId, 'OFFLINE_12345_6789');
      expect(restored.payload['totalAmount'], 850.0);
      expect(restored.lastError, 'SocketException: Connection refused');
    });

    test('OfflineOrderQueue queues orders, tracks pendingCount, and clears queue', () async {
      final queue = Get.put(OfflineOrderQueue());
      expect(queue.pendingCount.value, 0);

      final payload = {
        'shopId': 'shop_001',
        'customerId': 'cust_99',
        'totalAmount': 500.0,
        'paymentMethod': 'cash',
      };

      final offlineId = await queue.queueOrder(
        payload,
        customerName: 'Offline Customer',
        customerMobile: '9999999999',
        totalAmount: 500.0,
        paymentMethod: 'cash',
      );

      expect(offlineId.startsWith('OFFLINE_'), true);
      expect(queue.pendingCount.value, 1);
      expect(queue.queuedOrders.length, 1);

      await queue.clearQueue();
      expect(queue.pendingCount.value, 0);
      expect(queue.queuedOrders.isEmpty, true);
    });
  });
}
