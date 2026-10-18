import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/core/hardware/esc_pos_generator.dart';
import 'package:pos_system/core/hardware/printer_service.dart';
import 'package:pos_system/core/hardware/weighing_scale_service.dart';
import 'package:pos_system/core/hardware/cfd_service.dart';
import 'package:pos_system/data/models/product_model.dart';
import 'package:pos_system/modules/pos/controllers/cart_controller.dart';

void main() {
  group('ESC/POS Command Encoder Tests', () {
    test('reset generates ESC @ bytes', () {
      final gen = EscPosGenerator();
      gen.reset();
      final bytes = gen.toBytes();
      expect(bytes, [0x1B, 0x40]);
    });

    test('align commands generate ESC a n bytes', () {
      final gen = EscPosGenerator();
      gen.setAlign(EscPosAlign.center);
      expect(gen.toBytes(), [0x1B, 0x61, 0x01]);

      final gen2 = EscPosGenerator();
      gen2.setAlign(EscPosAlign.right);
      expect(gen2.toBytes(), [0x1B, 0x61, 0x02]);

      final gen3 = EscPosGenerator();
      gen3.setAlign(EscPosAlign.left);
      expect(gen3.toBytes(), [0x1B, 0x61, 0x00]);
    });

    test('openCashDrawer generates ESC p m t1 t2 for Pin 2 and Pin 5', () {
      final genPin2 = EscPosGenerator();
      genPin2.openCashDrawer(pin: 2);
      expect(genPin2.toBytes(), [0x1B, 0x70, 0x00, 0x19, 0xFA]);

      final genPin5 = EscPosGenerator();
      genPin5.openCashDrawer(pin: 5);
      expect(genPin5.toBytes(), [0x1B, 0x70, 0x01, 0x19, 0xFA]);
    });

    test('paper cut generates GS V command', () {
      final gen = EscPosGenerator();
      gen.cut(partial: true);
      final bytes = gen.toBytes();
      // Line feed 3 times: [0x0A, 0x0A, 0x0A], then GS V 1: [0x1D, 0x56, 0x01]
      expect(bytes, [0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x01]);
    });

    test('row2 justifies text properly across paper width', () {
      final gen = EscPosGenerator(paperSize: EscPosPaperSize.mm58); // 32 chars
      gen.row2('Apples', 'Rs.150.00');
      final bytes = gen.toBytes();
      // Extract printable ASCII characters (excluding ESC/POS control command bytes)
      final printable = bytes.where((b) => b >= 32 && b <= 126).toList();
      final line = String.fromCharCodes(printable);
      expect(line.length, 32);
      expect(line.startsWith('Apples'), isTrue);
      expect(line.endsWith('Rs.150.00'), isTrue);
    });
  });

  group('PrinterService Tests', () {
    late PrinterService printer;

    setUp(() {
      printer = PrinterService();
      printer.connectionType.value = PrinterConnectionType.virtual;
      printer.managerPin.value = '9999';
      printer.drawerRequiresPin.value = true;
    });

    test('kickCashDrawer validates manager PIN', () async {
      // Wrong PIN
      final fail = await printer.kickCashDrawer(managerPinInput: '1111');
      expect(fail, isFalse);

      // Correct PIN
      final success = await printer.kickCashDrawer(managerPinInput: '9999');
      expect(success, isTrue);
    });

    test('printOrderReceipt formats receipt and captures virtual text', () async {
      final receiptData = OrderReceiptData(
        shopName: 'Green Orchard Fruits',
        orderId: 'ORD_TEST_101',
        orderDate: DateTime(2026, 5, 10, 14, 30),
        customerName: 'Aarav Patel',
        customerMobile: '9876543210',
        items: const [
          ReceiptItemData(
            name: 'Alphonso Mango',
            quantity: 2.5,
            unit: 'kg',
            price: 200.0,
            total: 500.0,
          ),
        ],
        subtotal: 500.0,
        totalAmount: 500.0,
        paymentMethod: 'cash',
        cashTendered: 1000.0,
        changeReturned: 500.0,
      );

      final ok = await printer.printOrderReceipt(receiptData);
      expect(ok, isTrue);
      expect(printer.lastReceiptText.value.contains('Green Orchard Fruits'), isTrue);
      expect(printer.lastReceiptText.value.contains('ORD_TEST_101'), isTrue);
      expect(printer.lastReceiptText.value.contains('Alphonso Mango'), isTrue);
      expect(printer.lastReceiptText.value.contains('Rs.500.00'), isTrue);
    });
  });

  group('WeighingScaleService Tests', () {
    late WeighingScaleService scale;

    setUp(() {
      scale = WeighingScaleService();
      scale.scaleMode.value = ScaleMode.simulator;
    });

    test('zero resets tare and current weight', () {
      scale.currentWeight.value = 1.500;
      scale.tareWeight.value = 0.200;

      scale.zero();

      expect(scale.currentWeight.value, 0.0);
      expect(scale.tareWeight.value, 0.0);
    });

    test('tare moves current weight into tare reference', () {
      scale.currentWeight.value = 0.350; // container weight
      scale.tare();

      expect(scale.tareWeight.value, 0.350);
      expect(scale.currentWeight.value, 0.0);
    });
  });

  group('CustomerFacingDisplay (CFD) Service Tests', () {
    late CfdService cfd;
    late CartController cart;

    setUp(() {
      cfd = CfdService();
      cart = CartController();
    });

    test('syncWithCart updates CFD items and total', () {
      cfd.resetToWelcome();
      expect(cfd.state.value, CfdScreenState.welcome);

      final prod = ProductModel(
        productId: 'prod_99',
        shopId: 'shop_1',
        name: 'Kashmiri Apple',
        price: 180.0,
        measurementType: 'kg',
        stock: 50.0,
        status: 'Active',
        createdAt: DateTime.now(),
      );

      cart.addItem(prod, 2.0); // 360
      cfd.syncWithCart(cart);

      expect(cfd.state.value, CfdScreenState.ringing);
      expect(cfd.grandTotal.value, 360.0);
      expect(cfd.displayItems.length, 1);
      expect(cfd.lastScannedItem.value, 'Kashmiri Apple');
    });

    test('showPaymentScreen updates CFD to paying state', () {
      cfd.showPaymentScreen(
        total: 500.0,
        upi: 'upi://pay?pa=test@upi&am=500.00',
        method: 'upi',
      );

      expect(cfd.state.value, CfdScreenState.paying);
      expect(cfd.grandTotal.value, 500.0);
      expect(cfd.upiUri.value.contains('test@upi'), isTrue);
    });

    test('showCompletedScreen updates CFD to completed state', () {
      cfd.showCompletedScreen(orderId: 'ORD_999', change: 50.0);

      expect(cfd.state.value, CfdScreenState.completed);
      expect(cfd.changeReturned.value, 50.0);
    });
  });
}
