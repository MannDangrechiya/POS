import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_system/core/hardware/esc_pos_generator.dart';
import 'package:pos_system/core/hardware/printer_service.dart';
import 'package:pos_system/core/hardware/terminal_service.dart';
import 'package:pos_system/data/models/product_model.dart';
import 'package:pos_system/data/models/order_model.dart';
import 'package:pos_system/data/models/shift_model.dart';
import 'package:pos_system/data/models/refund_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 5 - Multi-Register Terminal Configuration', () {
    test('TerminalService defaults and persistence', () async {
      final terminal = TerminalService.instance;
      await terminal.loadSettings();

      // Check defaults
      expect(terminal.terminalId.value, 'REG-01');
      expect(terminal.terminalName.value, 'Counter 1 (Main Till)');
      expect(terminal.branchCode.value, 'MAIN');

      // Update settings
      await terminal.saveSettings(
        id: 'REG-WHOLESALE-02',
        name: 'Wholesale Dispatch Counter 2',
        branch: 'MKT-YARD',
      );

      expect(terminal.terminalId.value, 'REG-WHOLESALE-02');
      expect(terminal.terminalName.value, 'Wholesale Dispatch Counter 2');
      expect(terminal.branchCode.value, 'MKT-YARD');

      // Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(TerminalService.prefTerminalId), 'REG-WHOLESALE-02');
      expect(prefs.getString(TerminalService.prefTerminalName), 'Wholesale Dispatch Counter 2');
      expect(prefs.getString(TerminalService.prefBranchCode), 'MKT-YARD');
    });

    test('OrderModel, ShiftModel, and RefundModel include terminalId', () {
      final now = DateTime.now();

      // OrderModel
      final order = OrderModel(
        orderId: 'ORD-101',
        shopId: 'SHOP-1',
        customerId: 'CUST-1',
        employeeId: 'EMP-1',
        totalAmount: 450.0,
        paymentMethod: 'cash',
        paymentStatus: 'Success',
        orderStatus: 'locked',
        terminalId: 'REG-02',
        createdAt: now,
      );
      final orderMap = order.toMap();
      expect(orderMap['terminalId'], 'REG-02');

      final parsedOrder = OrderModel.fromMap(orderMap);
      expect(parsedOrder.terminalId, 'REG-02');

      // ShiftModel
      final shift = ShiftModel(
        shiftId: 'SHIFT-201',
        shopId: 'SHOP-1',
        cashierId: 'EMP-1',
        cashierName: 'Ramesh',
        openingFloat: 2000.0,
        status: 'open',
        openedAt: now,
        terminalId: 'REG-03',
      );
      final shiftMap = shift.toMap();
      expect(shiftMap['terminalId'], 'REG-03');

      final parsedShift = ShiftModel.fromMap(shiftMap);
      expect(parsedShift.terminalId, 'REG-03');

      // RefundModel
      final refund = RefundModel(
        refundId: 'REF-301',
        shopId: 'SHOP-1',
        orderId: 'ORD-101',
        employeeId: 'EMP-1',
        shiftId: 'SHIFT-201',
        terminalId: 'REG-03',
        items: const [],
        totalRefundAmount: 120.0,
        refundMethod: 'cash',
        createdAt: now,
      );
      final refundMap = refund.toMap();
      expect(refundMap['terminalId'], 'REG-03');

      final parsedRefund = RefundModel.fromMap(refundMap);
      expect(parsedRefund.terminalId, 'REG-03');
    });
  });

  group('Phase 5 - Barcode Label Printing & ESC/POS Generator', () {
    test('EscPosGenerator emits standard Code128 barcode commands', () {
      final generator = EscPosGenerator(paperSize: EscPosPaperSize.mm80);
      generator.reset();
      generator.barcode128('890123456789', height: 60, width: 2, showHri: true);

      final bytes = generator.toBytes();
      expect(bytes, isNotEmpty);

      // Verify reset: 0x1B, 0x40
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x40);

      // Verify GS h (height 60 = 0x3C): [0x1D, 0x68, 0x3C]
      expect(bytes.contains(0x1D), isTrue);
      final hIdx = bytes.indexOf(0x68);
      expect(hIdx, greaterThan(0));
      expect(bytes[hIdx + 1], 60);

      // Verify GS k 73 (Code128): [0x1D, 0x6B, 73, ...]
      final kIdx = bytes.indexOf(0x6B);
      expect(kIdx, greaterThan(0));
      expect(bytes[kIdx + 1], 73);
    });

    test('EscPosGenerator emits 2D QR Code commands', () {
      final generator = EscPosGenerator(paperSize: EscPosPaperSize.mm80);
      generator.reset();
      generator.qrCode('upi://pay?pa=shop@upi&am=250.00', size: 6);

      final bytes = generator.toBytes();
      expect(bytes, isNotEmpty);

      // Verify ESC/POS QR sequence contains 0x1D, 0x28, 0x6B (GS ( k)
      expect(bytes.contains(0x28), isTrue);
      expect(bytes.contains(0x6B), isTrue);
    });

    test('PrinterService prints adhesive fruit punnet barcode label', () async {
      final printer = PrinterService.instance;
      final ok = await printer.printProductLabel(
        productName: 'Mahabaleshwar Strawberries',
        price: 160.0,
        weightKg: 0.500,
        unit: 'kg',
        barcode: '890400112233',
        shopName: 'Fresh Fruit Mart',
      );

      expect(ok, isTrue);
      expect(printer.lastReceiptText.value, contains('PRODUCT LABEL'));
      expect(printer.lastReceiptText.value, contains('MAHABALESHWAR STRAWBERRIES'));
      expect(printer.lastReceiptText.value, contains('0.500 kg'));
      expect(printer.lastReceiptText.value, contains('Rs.160.00'));
      expect(printer.lastReceiptText.value, contains('890400112233'));
    });

    test('OrderReceipt includes terminal / register ID in printed ticket', () async {
      final printer = PrinterService.instance;
      final receiptData = OrderReceiptData(
        orderId: 'ORD-9999',
        terminalId: 'TILL-SOUTH-01',
        orderDate: DateTime(2026, 10, 18, 14, 30),
        customerName: 'Vikram',
        customerMobile: '9876543210',
        items: [
          const ReceiptItemData(
            name: 'Kashmir Apple',
            quantity: 2.0,
            unit: 'kg',
            price: 150.0,
            total: 300.0,
          ),
        ],
        subtotal: 300.0,
        totalAmount: 300.0,
        paymentMethod: 'cash',
      );

      final ok = await printer.printOrderReceipt(receiptData);
      expect(ok, isTrue);
      expect(printer.lastReceiptText.value, contains('TILL-SOUTH-01'));
      expect(printer.lastReceiptText.value, contains('Order ID : ORD-9999'));
    });
  });

  group('Phase 5 - Wholesale Analytics, Margin & Spoilage Calculations', () {
    test('ProductModel supports wholesale costPrice', () {
      final product = ProductModel(
        productId: 'P-KIWI',
        shopId: 'SHOP-1',
        name: 'Zespri Gold Kiwi',
        price: 320.0,
        costPrice: 220.0, // Wholesale purchase cost
        measurementType: 'box',
        stock: 50.0,
        status: 'Active',
        createdAt: DateTime.now(),
      );

      expect(product.costPrice, 220.0);
      final map = product.toMap();
      expect(map['costPrice'], 220.0);

      final fromMap = ProductModel.fromMap(map);
      expect(fromMap.costPrice, 220.0);

      final updated = product.copyWith(costPrice: 240.0);
      expect(updated.costPrice, 240.0);
    });

    test('Gross margin and profit formulas evaluate accurately', () {
      const revenue = 150000.0;
      const cogs = 105000.0;
      final grossProfit = revenue - cogs;
      final marginPercent = (grossProfit / revenue) * 100;

      expect(grossProfit, 45000.0);
      expect(marginPercent, closeTo(30.0, 0.01));

      // Spoilage calculation
      const spoilageLoss = 4500.0;
      final spoilageRate = (spoilageLoss / revenue) * 100;
      expect(spoilageRate, closeTo(3.0, 0.01));
    });

    test('Wholesale volume tier categorization', () {
      const vol1 = 5.0; // kg
      const vol2 = 25.0; // kg
      const vol3 = 60.0; // kg crate

      String classifyVolume(double kg) {
        if (kg >= 50.0) return 'Wholesale Tier 2 (>50 kg Crate)';
        if (kg >= 10.0) return 'Wholesale Tier 1 (10-50 kg)';
        return 'Retail (<10 kg)';
      }

      expect(classifyVolume(vol1), 'Retail (<10 kg)');
      expect(classifyVolume(vol2), 'Wholesale Tier 1 (10-50 kg)');
      expect(classifyVolume(vol3), 'Wholesale Tier 2 (>50 kg Crate)');
    });

    test('Customer Khata credit exposure and limit utilization', () {
      const currentBalance = 8500.0;
      const creditLimit = 10000.0;
      final util = (currentBalance / creditLimit) * 100;

      expect(util, 85.0);
      expect(util >= 80.0, isTrue); // High exposure warning trigger
    });
  });
}
