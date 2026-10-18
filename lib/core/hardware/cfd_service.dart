import 'dart:async';
import 'package:get/get.dart';
import '../../modules/pos/controllers/cart_controller.dart';

/// States for Customer Facing Display (CFD)
enum CfdScreenState {
  welcome,    // Idle screen with store logo, time, promotional banner
  ringing,    // Customer cart being scanned item by item
  paying,     // Checkout screen with grand total & dynamic UPI QR code
  completed,  // "Thank you!" screen with order confirmation
}

/// Service managing Customer Facing Display (CFD) state & reactive broadcast
class CfdService extends GetxService {
  static CfdService get instance => Get.isRegistered<CfdService>()
      ? Get.find<CfdService>()
      : Get.put(CfdService());

  // Observables
  final Rx<CfdScreenState> state = CfdScreenState.welcome.obs;
  final RxString storeName = 'Fresh Fruit Mart'.obs;
  final RxString storeTagline = 'Farm Fresh Quality Every Day'.obs;
  final RxString customerName = ''.obs;

  final RxDouble subtotal = 0.0.obs;
  final RxDouble discount = 0.0.obs;
  final RxDouble grandTotal = 0.0.obs;
  final RxString upiUri = ''.obs;
  final RxString paymentMethod = ''.obs;
  final RxDouble cashTendered = 0.0.obs;
  final RxDouble changeReturned = 0.0.obs;
  final RxString lastScannedItem = ''.obs;
  final RxDouble lastScannedPrice = 0.0.obs;

  final RxList<CartItem> displayItems = <CartItem>[].obs;
  Timer? _completeTimer;

  /// Synchronize CFD with POS Cart
  void syncWithCart(CartController cart) {
    if (state.value == CfdScreenState.paying || state.value == CfdScreenState.completed) {
      return;
    }

    if (cart.isEmpty) {
      state.value = CfdScreenState.welcome;
      displayItems.clear();
      grandTotal.value = 0.0;
      subtotal.value = 0.0;
      return;
    }

    state.value = CfdScreenState.ringing;
    displayItems.assignAll(cart.items);
    subtotal.value = cart.subtotal;
    discount.value = cart.discountAmount.value;
    grandTotal.value = cart.totalAmount;
    customerName.value = cart.customerName.value;

    if (cart.items.isNotEmpty) {
      final last = cart.items.last;
      lastScannedItem.value = last.product.name;
      lastScannedPrice.value = last.totalPrice;
    }
  }

  /// Trigger payment state on customer display
  void showPaymentScreen({
    required double total,
    required String upi,
    required String method,
    double? tendered,
    double? change,
  }) {
    _completeTimer?.cancel();
    state.value = CfdScreenState.paying;
    grandTotal.value = total;
    upiUri.value = upi;
    paymentMethod.value = method;
    cashTendered.value = tendered ?? total;
    changeReturned.value = change ?? 0.0;
  }

  /// Trigger completion state on customer display
  void showCompletedScreen({
    required String orderId,
    double? change,
  }) {
    _completeTimer?.cancel();
    state.value = CfdScreenState.completed;
    changeReturned.value = change ?? 0.0;

    // Return to welcome after 8 seconds
    _completeTimer = Timer(const Duration(seconds: 8), () {
      resetToWelcome();
    });
  }

  /// Reset CFD to welcome screen
  void resetToWelcome() {
    _completeTimer?.cancel();
    state.value = CfdScreenState.welcome;
    displayItems.clear();
    grandTotal.value = 0.0;
    subtotal.value = 0.0;
    upiUri.value = '';
    paymentMethod.value = '';
    customerName.value = '';
  }
}
