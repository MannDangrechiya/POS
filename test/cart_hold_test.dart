import 'package:flutter_test/flutter_test.dart';
import 'package:pos_system/data/models/product_model.dart';
import 'package:pos_system/modules/pos/controllers/cart_controller.dart';

void main() {
  group('CartController Phase 1 High-Speed POS Verification', () {
    late CartController cartController;

    final dummyProduct1 = ProductModel(
      productId: 'prod_1',
      shopId: 'shop_1',
      name: 'Fresh Mango',
      categoryId: 'cat_fruit',
      price: 150.0,
      measurementType: 'kg',
      stock: 50.0,
      status: 'Active',
      barcode: '8901234567890',
      createdAt: DateTime.now(),
    );

    final dummyProduct2 = ProductModel(
      productId: 'prod_2',
      shopId: 'shop_1',
      name: 'Shimla Apple',
      categoryId: 'cat_fruit',
      price: 200.0,
      measurementType: 'kg',
      stock: 40.0,
      status: 'Active',
      barcode: '8901234567891',
      createdAt: DateTime.now(),
    );

    setUp(() {
      cartController = CartController();
    });

    test('addItem correctly computes totalAmount and itemCount', () {
      cartController.addItem(dummyProduct1, 2.0); // 150 * 2 = 300
      cartController.addItem(dummyProduct2, 1.5); // 200 * 1.5 = 300

      expect(cartController.items.length, 2);
      expect(cartController.totalAmount, 600.0);
      expect(cartController.itemCount, 2);
    });

    test('Customer info binding works correctly', () {
      cartController.setCustomer('Ramesh Patel', '9876543210');
      expect(cartController.customerName.value, 'Ramesh Patel');
      expect(cartController.customerMobile.value, '9876543210');

      cartController.clearCustomer();
      expect(cartController.customerName.value, '');
      expect(cartController.customerMobile.value, '');
    });

    test('parkCurrentCart captures items, customer info, and clears active cart', () {
      cartController.addItem(dummyProduct1, 3.0); // 450
      cartController.setCustomer('Pooja Shah', '9898989898');

      expect(cartController.parkedCarts.length, 0);
      final success = cartController.parkCurrentCart();

      expect(success, isTrue);
      expect(cartController.parkedCarts.length, 1);
      final parked = cartController.parkedCarts.first;
      expect(parked.customerName, 'Pooja Shah');
      expect(parked.totalAmount, 450.0);
      expect(cartController.items.isEmpty, isTrue);
      expect(cartController.customerName.value, '');
      expect(cartController.customerMobile.value, '');
    });

    test('recallCart restores items and customer info into active cart', () {
      cartController.addItem(dummyProduct1, 2.0);
      cartController.setCustomer('Kiran Mehta', '9123456789');
      final success = cartController.parkCurrentCart();
      expect(success, isTrue);
      expect(cartController.isEmpty, isTrue);
      final parkedId = cartController.parkedCarts.first.id;

      final recalled = cartController.recallCart(parkedId);
      expect(recalled, isTrue);
      expect(cartController.items.length, 1);
      expect(cartController.customerName.value, 'Kiran Mehta');
      expect(cartController.customerMobile.value, '9123456789');
      expect(cartController.totalAmount, 300.0);
      expect(cartController.parkedCarts.length, 0);
    });

    test('discardParkedCart removes parked cart without affecting active cart', () {
      cartController.addItem(dummyProduct1, 1.0);
      final success = cartController.parkCurrentCart();
      expect(success, isTrue);
      expect(cartController.parkedCarts.length, 1);
      final parkedId = cartController.parkedCarts.first.id;

      cartController.discardParkedCart(parkedId);
      expect(cartController.parkedCarts.isEmpty, isTrue);
    });
  });
}
