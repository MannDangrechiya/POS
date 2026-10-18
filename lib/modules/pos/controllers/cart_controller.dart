import 'package:get/get.dart';
import 'package:pos_system/data/models/product_model.dart';
import '../../../core/hardware/cfd_service.dart';

/// Cart item model
class CartItem {
  final ProductModel product;
  final double quantityOrWeight;
  final double priceSnapshot;

  CartItem({
    required this.product,
    required this.quantityOrWeight,
    required this.priceSnapshot,
  });

  double get totalPrice => quantityOrWeight * priceSnapshot;
}

/// Represents an order placed on hold so the cashier can serve another customer
class ParkedCart {
  final String id;
  final String label;
  final String customerName;
  final String customerMobile;
  final List<CartItem> items;
  final DateTime parkedAt;
  final double discountAmount;
  final String discountReason;

  ParkedCart({
    required this.id,
    required this.label,
    this.customerName = '',
    this.customerMobile = '',
    required this.items,
    required this.parkedAt,
    this.discountAmount = 0.0,
    this.discountReason = '',
  });

  double get totalAmount =>
      items.fold(0.0, (sum, item) => sum + item.totalPrice);
  int get itemCount => items.length;
}

/// Cart controller for managing POS cart UI state
class CartController extends GetxController {
  final RxList<CartItem> _items = <CartItem>[].obs;

  // Tax Engine (GST in India / Local sales tax)
  final RxDouble taxRatePercent = 0.0.obs;

  // Discount Engine
  final RxDouble discountAmount = 0.0.obs;
  final RxString discountReason = ''.obs;

  @override
  void onInit() {
    super.onInit();
    ever(_items, (_) {
      if (Get.isRegistered<CfdService>()) {
        CfdService.instance.syncWithCart(this);
      }
    });
    // Also sync CFD on discount change
    ever(discountAmount, (_) {
      if (Get.isRegistered<CfdService>()) {
        CfdService.instance.syncWithCart(this);
      }
    });
  }

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.length;

  /// Raw item subtotal before discounts and taxes
  double get subtotal {
    return _items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  /// Taxable base amount after subtracting cart discount
  double get taxableAmount {
    return (subtotal - discountAmount.value).clamp(0.0, double.infinity);
  }

  /// Computed tax (e.g. 5% GST)
  double get taxAmount {
    return (taxableAmount * taxRatePercent.value) / 100.0;
  }

  /// Central GST component (50% of total GST)
  double get cgstAmount => taxAmount / 2.0;

  /// State GST component (50% of total GST)
  double get sgstAmount => taxAmount / 2.0;

  /// Final payable amount including taxes
  double get totalAmount {
    return taxableAmount + taxAmount;
  }

  bool get isEmpty => _items.isEmpty;

  /// Apply a percentage discount (e.g. 10% off)
  void applyDiscountPercent(double percent, {String reason = ''}) {
    final validPercent = percent.clamp(0.0, 100.0);
    discountAmount.value = (subtotal * validPercent) / 100.0;
    discountReason.value = reason.isNotEmpty ? reason : '${validPercent.toStringAsFixed(0)}% Off';
  }

  /// Apply a flat rupee discount (e.g. Rs. 50 off)
  void applyDiscountFlat(double amount, {String reason = ''}) {
    discountAmount.value = amount.clamp(0.0, subtotal);
    discountReason.value = reason.isNotEmpty ? reason : 'Flat Rs.${amount.toStringAsFixed(0)} Off';
  }

  /// Reset applied discount
  void clearDiscount() {
    discountAmount.value = 0.0;
    discountReason.value = '';
  }

  /// Update tax rate percentage (from shop settings)
  void setTaxRate(double rate) {
    taxRatePercent.value = rate.clamp(0.0, 100.0);
  }

  // Active Customer state
  final RxString customerName = ''.obs;
  final RxString customerMobile = ''.obs;

  void setCustomer(String name, String mobile) {
    customerName.value = name.trim();
    customerMobile.value = mobile.trim();
  }

  void clearCustomer() {
    customerName.value = '';
    customerMobile.value = '';
  }

  // Multi-cart parking (Hold Orders)
  final RxList<ParkedCart> _parkedCarts = <ParkedCart>[].obs;
  List<ParkedCart> get parkedCarts => List.unmodifiable(_parkedCarts);
  int get parkedCount => _parkedCarts.length;

  /// Add item to cart
  void addItem(ProductModel product, double quantityOrWeight) {
    // Check if product already exists in cart
    final existingIndex = _items.indexWhere(
      (item) => item.product.productId == product.productId,
    );

    if (existingIndex >= 0) {
      // Update existing item quantity
      final existingItem = _items[existingIndex];
      final newQuantity = existingItem.quantityOrWeight + quantityOrWeight;
      
      // Validate stock
      if (newQuantity > product.stock) {
        throw Exception(
          'Insufficient stock. Available: ${product.stock}, Requested: $newQuantity',
        );
      }

      final activePrice = product.getPriceForQuantity(newQuantity);

      // Update item by removing and re-adding to ensure reactivity
      _items.removeAt(existingIndex);
      _items.insert(existingIndex, CartItem(
        product: product,
        quantityOrWeight: newQuantity,
        priceSnapshot: activePrice,
      ));
    } else {
      final activePrice = product.getPriceForQuantity(quantityOrWeight);
      // Add new item
      _items.add(
        CartItem(
          product: product,
          quantityOrWeight: quantityOrWeight,
          priceSnapshot: activePrice,
        ),
      );
    }
  }

  /// Update item quantity
  void updateQuantity(String productId, double newQuantity) {
    final index = _items.indexWhere(
      (item) => item.product.productId == productId,
    );

    if (index < 0) return;

    final item = _items[index];
    
    // Validate stock
    if (newQuantity > item.product.stock) {
      throw Exception(
        'Insufficient stock. Available: ${item.product.stock}, Requested: $newQuantity',
      );
    }

    if (newQuantity <= 0) {
      removeItem(productId);
      return;
    }

    final activePrice = item.product.getPriceForQuantity(newQuantity);

    // Update item by removing and re-adding to ensure reactivity
    _items.removeAt(index);
    _items.insert(index, CartItem(
      product: item.product,
      quantityOrWeight: newQuantity,
      priceSnapshot: activePrice,
    ));
  }

  /// Remove item from cart
  void removeItem(String productId) {
    _items.removeWhere((item) => item.product.productId == productId);
  }

  /// Clear cart and active customer
  void clear() {
    _items.clear();
    clearCustomer();
    clearDiscount();
  }

  /// Park current cart. Returns false if cart is empty or limit (5) reached.
  bool parkCurrentCart({String? customLabel}) {
    if (_items.isEmpty) return false;
    if (_parkedCarts.length >= 5) return false;

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final name = customerName.value.trim();
    final mobile = customerMobile.value.trim();
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final label = customLabel?.trim().isNotEmpty == true
        ? customLabel!.trim()
        : (name.isNotEmpty ? '$name ($timeStr)' : 'Hold #${_parkedCarts.length + 1} ($timeStr)');

    _parkedCarts.add(
      ParkedCart(
        id: id,
        label: label,
        customerName: name,
        customerMobile: mobile,
        items: List.from(_items),
        parkedAt: now,
        discountAmount: discountAmount.value,
        discountReason: discountReason.value,
      ),
    );

    _items.clear();
    clearCustomer();
    clearDiscount();
    return true;
  }

  /// Recall a parked cart. If current cart has items, they will be parked first.
  bool recallCart(String parkedId) {
    final index = _parkedCarts.indexWhere((c) => c.id == parkedId);
    if (index < 0) return false;

    final targetCart = _parkedCarts.removeAt(index);

    // If current cart already has items, park them first
    if (_items.isNotEmpty) {
      parkCurrentCart();
    }

    _items.clear();
    _items.addAll(targetCart.items);
    setCustomer(targetCart.customerName, targetCart.customerMobile);
    discountAmount.value = targetCart.discountAmount;
    discountReason.value = targetCart.discountReason;
    return true;
  }

  /// Discard a parked cart without recalling it
  void discardParkedCart(String parkedId) {
    _parkedCarts.removeWhere((c) => c.id == parkedId);
  }

  /// Get cart item by product ID
  CartItem? getItem(String productId) {
    try {
      return _items.firstWhere(
        (item) => item.product.productId == productId,
      );
    } catch (e) {
      return null;
    }
  }
}
