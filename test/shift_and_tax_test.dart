import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:pos_system/data/models/shift_model.dart';
import 'package:pos_system/data/models/product_model.dart';
import 'package:pos_system/modules/pos/controllers/cart_controller.dart';
import 'package:pos_system/core/hardware/printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShiftModel & Cash Drawer Balancing Tests', () {
    test('expectedCash and grossSales are correctly calculated', () {
      final movements = [
        ShiftMovement(
          id: 'm1',
          type: 'cash_in',
          amount: 500.0,
          reason: 'Added small change',
          timestamp: DateTime.now(),
        ),
        ShiftMovement(
          id: 'm2',
          type: 'cash_out',
          amount: 200.0,
          reason: 'Paid delivery boy',
          timestamp: DateTime.now(),
        ),
      ];

      final shift = ShiftModel(
        shiftId: 'shift_123',
        shopId: 'shop_001',
        cashierId: 'user_456',
        cashierName: 'Ramesh Cashier',
        openingFloat: 1000.0,
        status: 'open',
        openedAt: DateTime.now(),
        cashSales: 3500.0,
        upiSales: 2000.0,
        cardSales: 500.0,
        orderCount: 25,
        movements: movements,
      );

      expect(shift.cashInTotal, 500.0);
      expect(shift.cashOutTotal, 200.0);
      // Expected Drawer Cash = 1000 (float) + 3500 (cash sales) + 500 (cash in) - 200 (cash out) = 4800
      expect(shift.expectedCash, 4800.0);
      // Gross Sales = 3500 (cash) + 2000 (upi) + 500 (card) = 6000
      expect(shift.grossSales, 6000.0);
    });

    test('Blind count variance is correctly calculated for balanced, overage, and shortage', () {
      final baseShift = ShiftModel(
        shiftId: 'shift_abc',
        shopId: 'shop_001',
        cashierId: 'cashier_1',
        cashierName: 'Pooja',
        openingFloat: 1000.0,
        status: 'open',
        openedAt: DateTime.now(),
        cashSales: 1500.0,
      );
      // expectedCash = 1000 + 1500 = 2500

      // Case 1: Balanced (actual == expected)
      final balancedCount = 2500.0;
      final balancedDiff = balancedCount - baseShift.expectedCash;
      expect(balancedDiff, 0.0);

      // Case 2: Overage (+50)
      final overageCount = 2550.0;
      final overageDiff = overageCount - baseShift.expectedCash;
      expect(overageDiff, 50.0);

      // Case 3: Shortage (-100)
      final shortageCount = 2400.0;
      final shortageDiff = shortageCount - baseShift.expectedCash;
      expect(shortageDiff, -100.0);
    });

    test('ShiftModel serialization toMap and fromMap preserves all fields', () {
      final now = DateTime.now();
      final shift = ShiftModel(
        shiftId: 's1',
        shopId: 'sh1',
        cashierId: 'c1',
        cashierName: 'John',
        openingFloat: 500.0,
        status: 'closed',
        openedAt: now,
        closedAt: now.add(const Duration(hours: 8)),
        cashSales: 1200.0,
        upiSales: 800.0,
        cardSales: 400.0,
        orderCount: 15,
        actualCashCounted: 1700.0,
        difference: 0.0,
        notes: 'End of day audit perfect',
      );

      final map = shift.toMap();
      expect(map['shiftId'], 's1');
      expect(map['openingFloat'], 500.0);
      expect(map['cashSales'], 1200.0);
      expect(map['actualCashCounted'], 1700.0);

      final restored = ShiftModel.fromMap(map);
      expect(restored.shiftId, 's1');
      expect(restored.openingFloat, 500.0);
      expect(restored.cashSales, 1200.0);
      expect(restored.grossSales, 2400.0);
      expect(restored.actualCashCounted, 1700.0);
      expect(restored.isOpen, isFalse);
    });
  });

  group('CartController Tax and Discount Engine Tests', () {
    late CartController cartController;

    setUp(() {
      Get.reset();
      cartController = Get.put(CartController());
    });

    final apple = ProductModel(
      productId: 'p_apple',
      shopId: 'shop_1',
      name: 'Shimla Apple',
      categoryId: 'Fruits',
      price: 100.0,
      stock: 50.0,
      measurementType: 'kg',
      status: 'Active',
      createdAt: DateTime.now(),
    );

    final banana = ProductModel(
      productId: 'p_banana',
      shopId: 'shop_1',
      name: 'Robusta Banana',
      categoryId: 'Fruits',
      price: 50.0,
      stock: 100.0,
      measurementType: 'kg',
      status: 'Active',
      createdAt: DateTime.now(),
    );

    test('initial values are zero', () {
      expect(cartController.subtotal, 0.0);
      expect(cartController.discountAmount.value, 0.0);
      expect(cartController.taxAmount, 0.0);
      expect(cartController.totalAmount, 0.0);
    });

    test('subtotal sums item prices accurately', () {
      cartController.addItem(apple, 2.0); // 2 x 100 = 200
      cartController.addItem(banana, 3.0); // 3 x 50 = 150
      expect(cartController.subtotal, 350.0);
    });

    test('applies percentage discount and computes GST 5% breakdown correctly', () {
      cartController.addItem(apple, 2.0); // 200
      cartController.addItem(banana, 2.0); // 100 -> Subtotal = 300
      cartController.setTaxRate(5.0); // 5% GST

      // Apply 10% discount
      cartController.applyDiscountPercent(10.0, reason: 'Special 10% Off');

      expect(cartController.discountAmount.value, 30.0); // 10% of 300 = 30
      expect(cartController.discountReason.value, 'Special 10% Off');

      // Taxable Base = Subtotal (300) - Discount (30) = 270
      expect(cartController.taxableAmount, 270.0);

      // Tax Amount = 5% of 270 = 13.5
      expect(cartController.taxAmount, 13.5);
      expect(cartController.cgstAmount, 6.75); // 13.5 / 2
      expect(cartController.sgstAmount, 6.75); // 13.5 / 2

      // Total Due = 270 + 13.5 = 283.5
      expect(cartController.totalAmount, 283.5);
    });

    test('applies flat rupee discount and clears discount', () {
      cartController.addItem(apple, 1.0); // 100
      cartController.setTaxRate(0.0); // 0% tax for clear isolation

      cartController.applyDiscountFlat(25.0);
      expect(cartController.discountAmount.value, 25.0);
      expect(cartController.totalAmount, 75.0);

      cartController.clearDiscount();
      expect(cartController.discountAmount.value, 0.0);
      expect(cartController.totalAmount, 100.0);
    });

    test('parkCurrentCart and recallCart preserve discount amount and reason', () {
      cartController.addItem(apple, 1.0); // 100
      cartController.applyDiscountPercent(20.0, reason: 'Staff 20%');

      final parked = cartController.parkCurrentCart(customLabel: 'Staff Hold');
      expect(parked, isTrue);
      expect(cartController.isEmpty, isTrue);
      expect(cartController.discountAmount.value, 0.0); // cleared for next customer

      // Recall cart
      final recalled = cartController.recallCart(cartController.parkedCarts.first.id);
      expect(recalled, isTrue);
      expect(cartController.itemCount, 1);
      expect(cartController.discountAmount.value, 20.0);
      expect(cartController.discountReason.value, 'Staff 20%');
    });
  });

  group('PrinterService Z-Report Generation Tests', () {
    test('printZReport generates detailed audit ticket in virtual mode', () async {
      final printer = PrinterService.instance;
      printer.connectionType.value = PrinterConnectionType.virtual;

      final shift = ShiftModel(
        shiftId: 'shift_audit_999',
        shopId: 'shop_main',
        cashierId: 'emp_01',
        cashierName: 'Suresh Kumar',
        openingFloat: 2000.0,
        status: 'closed',
        openedAt: DateTime(2026, 10, 18, 9, 0),
        closedAt: DateTime(2026, 10, 18, 17, 0),
        cashSales: 4500.0,
        upiSales: 3200.0,
        cardSales: 1100.0,
        orderCount: 42,
        movements: [
          ShiftMovement(
            id: 'm1',
            type: 'cash_in',
            amount: 500.0,
            reason: 'Added coins',
            timestamp: DateTime(2026, 10, 18, 11, 0),
          ),
          ShiftMovement(
            id: 'm2',
            type: 'cash_out',
            amount: 300.0,
            reason: 'Tea and coffee expenses',
            timestamp: DateTime(2026, 10, 18, 14, 0),
          ),
        ],
        actualCashCounted: 6700.0,
        difference: 0.0, // Expected = 2000 + 4500 + 500 - 300 = 6700
        notes: 'Drawer perfectly matched',
      );

      final success = await printer.printZReport(shift, shopName: 'Fresh Fruit Mart');
      expect(success, isTrue);

      final receipt = printer.lastReceiptText.value;
      expect(receipt.contains('Z-REPORT'), isTrue);
      expect(receipt.contains('Suresh Kumar'), isTrue);
      expect(receipt.contains('Gross Sales: Rs.8800.00'), isTrue);
      expect(receipt.contains('Opening Float: Rs.2000.00'), isTrue);
      expect(receipt.contains('Expected Cash: Rs.6700.00'), isTrue);
      expect(receipt.contains('Actual Counted: Rs.6700.00'), isTrue);
      expect(receipt.contains('[BALANCED]'), isTrue);
    });
  });
}
