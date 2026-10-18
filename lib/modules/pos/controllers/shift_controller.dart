import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../data/models/shift_model.dart';
import '../../../core/hardware/printer_service.dart';

/// Manages Cashier Shift Lifecycle, Float Management, Cash In/Out movements,
/// Blind Drawer Count auditing, and Z-Report generation.
class ShiftController extends GetxController {
  static ShiftController get instance => Get.isRegistered<ShiftController>()
      ? Get.find<ShiftController>()
      : Get.put(ShiftController());

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Rx<ShiftModel?> activeShift = Rx<ShiftModel?>(null);
  final RxBool isLoading = false.obs;
  final RxString error = ''.obs;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _shiftSub;

  bool get hasActiveShift => activeShift.value != null && activeShift.value!.isOpen;

  @override
  void onClose() {
    _shiftSub?.cancel();
    super.onClose();
  }

  /// Check if the cashier currently has an open shift in this shop
  Future<ShiftModel?> checkActiveShift(String shopId, String cashierId) async {
    try {
      isLoading.value = true;
      error.value = '';

      final query = await _firestore
          .collection('shifts')
          .where('shopId', isEqualTo: shopId)
          .where('cashierId', isEqualTo: cashierId)
          .where('status', isEqualTo: 'open')
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final shift = ShiftModel.fromFirestore(query.docs.first);
        activeShift.value = shift;
        _listenToShift(shift.shiftId);
        return shift;
      } else {
        activeShift.value = null;
        _shiftSub?.cancel();
        return null;
      }
    } catch (e) {
      error.value = 'Failed to check active shift: $e';
      debugPrint('[ShiftController] $e');
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  void _listenToShift(String shiftId) {
    _shiftSub?.cancel();
    _shiftSub = _firestore
        .collection('shifts')
        .doc(shiftId)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        final updated = ShiftModel.fromFirestore(doc);
        if (updated.isOpen) {
          activeShift.value = updated;
        } else {
          activeShift.value = null;
        }
      }
    });
  }

  /// Open a new cashier shift with an opening float
  Future<ShiftModel?> openShift({
    required String shopId,
    required String cashierId,
    required String cashierName,
    required double openingFloat,
    String notes = '',
  }) async {
    try {
      isLoading.value = true;
      error.value = '';

      final shiftRef = _firestore.collection('shifts').doc();
      final newShift = ShiftModel(
        shiftId: shiftRef.id,
        shopId: shopId,
        cashierId: cashierId,
        cashierName: cashierName,
        openingFloat: openingFloat,
        status: 'open',
        openedAt: DateTime.now(),
        notes: notes,
      );

      await shiftRef.set(newShift.toMap());
      activeShift.value = newShift;
      _listenToShift(shiftRef.id);

      // Auto pop cash drawer on shift start if configured
      if (PrinterService.instance.autoKickDrawerOnCash.value) {
        unawaited(PrinterService.instance.kickCashDrawer());
      }

      return newShift;
    } catch (e) {
      error.value = 'Failed to open shift: $e';
      debugPrint('[ShiftController] openShift error: $e');
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  /// Mid-shift petty cash movements (Cash In / Cash Out)
  Future<bool> recordCashMovement({
    required String type, // 'cash_in' or 'cash_out'
    required double amount,
    required String reason,
    required String authorizedBy,
  }) async {
    final current = activeShift.value;
    if (current == null) {
      error.value = 'No active shift found';
      return false;
    }

    try {
      isLoading.value = true;
      error.value = '';

      final movementId = DateTime.now().millisecondsSinceEpoch.toString();
      final movement = ShiftMovement(
        id: movementId,
        type: type,
        amount: amount,
        reason: reason,
        timestamp: DateTime.now(),
        authorizedBy: authorizedBy,
      );

      await _firestore.collection('shifts').doc(current.shiftId).update({
        'movements': FieldValue.arrayUnion([movement.toMap()]),
      });

      // Update local state immediately
      final updatedMovements = List<ShiftMovement>.from(current.movements)..add(movement);
      activeShift.value = ShiftModel(
        shiftId: current.shiftId,
        shopId: current.shopId,
        cashierId: current.cashierId,
        cashierName: current.cashierName,
        openingFloat: current.openingFloat,
        status: current.status,
        openedAt: current.openedAt,
        closedAt: current.closedAt,
        cashSales: current.cashSales,
        upiSales: current.upiSales,
        cardSales: current.cardSales,
        orderCount: current.orderCount,
        movements: updatedMovements,
        actualCashCounted: current.actualCashCounted,
        difference: current.difference,
        notes: current.notes,
      );

      // Pop drawer for cash movement
      await PrinterService.instance.kickCashDrawer();
      return true;
    } catch (e) {
      error.value = 'Failed to record cash movement: $e';
      debugPrint('[ShiftController] recordCashMovement error: $e');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Close shift with blind cash count & generate thermal Z-report
  Future<ShiftModel?> closeShiftBlindCount({
    required double countedCash,
    String notes = '',
    String shopName = 'Fruit POS Store',
    String shopAddress = '',
  }) async {
    final current = activeShift.value;
    if (current == null) {
      error.value = 'No active shift to close';
      return null;
    }

    try {
      isLoading.value = true;
      error.value = '';

      final expected = current.expectedCash;
      final diff = countedCash - expected;
      final closedTime = DateTime.now();

      final closedShift = ShiftModel(
        shiftId: current.shiftId,
        shopId: current.shopId,
        cashierId: current.cashierId,
        cashierName: current.cashierName,
        openingFloat: current.openingFloat,
        status: 'closed',
        openedAt: current.openedAt,
        closedAt: closedTime,
        cashSales: current.cashSales,
        upiSales: current.upiSales,
        cardSales: current.cardSales,
        orderCount: current.orderCount,
        movements: current.movements,
        actualCashCounted: countedCash,
        difference: diff,
        notes: notes,
      );

      await _firestore.collection('shifts').doc(current.shiftId).update({
        'status': 'closed',
        'closedAt': Timestamp.fromDate(closedTime),
        'actualCashCounted': countedCash,
        'difference': diff,
        'notes': notes,
      });

      _shiftSub?.cancel();
      activeShift.value = null;

      // Print Z-Report
      await PrinterService.instance.printZReport(
        closedShift,
        shopName: shopName,
        shopAddress: shopAddress,
      );

      return closedShift;
    } catch (e) {
      error.value = 'Failed to close shift: $e';
      debugPrint('[ShiftController] closeShiftBlindCount error: $e');
      return null;
    } finally {
      isLoading.value = false;
    }
  }
}
