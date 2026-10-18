import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../hardware/printer_service.dart';

/// Represents an order saved locally when offline
class QueuedOrder {
  final String offlineOrderId;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
  int retryAttempts;
  String? lastError;

  QueuedOrder({
    required this.offlineOrderId,
    required this.payload,
    required this.queuedAt,
    this.retryAttempts = 0,
    this.lastError,
  });

  Map<String, dynamic> toMap() {
    return {
      'offlineOrderId': offlineOrderId,
      'payload': payload,
      'queuedAt': queuedAt.toIso8601String(),
      'retryAttempts': retryAttempts,
      'lastError': lastError,
    };
  }

  factory QueuedOrder.fromMap(Map<String, dynamic> map) {
    return QueuedOrder(
      offlineOrderId: map['offlineOrderId'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map),
      queuedAt: DateTime.tryParse(map['queuedAt'] as String? ?? '') ?? DateTime.now(),
      retryAttempts: map['retryAttempts'] as int? ?? 0,
      lastError: map['lastError'] as String?,
    );
  }
}

/// Offline Order Queue Service
///
/// Automatically persists orders locally to SharedPreferences when network connectivity
/// is lost or Cloud Function times out. Kicks drawer, prints offline thermal receipts,
/// and sequentially replays queued orders to the server once connectivity is restored.
class OfflineOrderQueue extends GetxService {
  static OfflineOrderQueue get instance => Get.isRegistered<OfflineOrderQueue>()
      ? Get.find<OfflineOrderQueue>()
      : Get.put(OfflineOrderQueue());

  static const String _storageKey = 'pos_offline_orders_queue_v1';

  final RxInt pendingCount = 0.obs;
  final RxBool isSyncing = false.obs;
  final RxString lastSyncStatus = ''.obs;

  final List<QueuedOrder> _queue = [];
  Timer? _autoSyncTimer;

  @override
  void onInit() {
    super.onInit();
    _loadQueueFromStorage();
    // Auto-sync heartbeat every 30 seconds
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (pendingCount.value > 0 && !isSyncing.value) {
        syncPendingOrders();
      }
    });
  }

  @override
  void onClose() {
    _autoSyncTimer?.cancel();
    super.onClose();
  }

  List<QueuedOrder> get queuedOrders => List.unmodifiable(_queue);

  Future<void> _loadQueueFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString(_storageKey);
      if (rawJson != null && rawJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(rawJson);
        _queue.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _queue.add(QueuedOrder.fromMap(item));
          }
        }
        pendingCount.value = _queue.length;
        debugPrint('[OfflineOrderQueue] Loaded ${_queue.length} pending orders from local storage.');
      }
    } catch (e) {
      debugPrint('[OfflineOrderQueue] Error loading queued orders: $e');
    }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_queue.map((q) => q.toMap()).toList());
      await prefs.setString(_storageKey, encoded);
      pendingCount.value = _queue.length;
    } catch (e) {
      debugPrint('[OfflineOrderQueue] Error persisting queue: $e');
    }
  }

  /// Generates a local offline order ID, stores the order, triggers drawer & offline receipt
  Future<String> queueOrder(
    Map<String, dynamic> payload, {
    required String customerName,
    required String customerMobile,
    required double totalAmount,
    required String paymentMethod,
    List<ReceiptItemData>? receiptItems,
  }) async {
    final offlineOrderId = 'OFFLINE_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    final queuedOrder = QueuedOrder(
      offlineOrderId: offlineOrderId,
      payload: payload,
      queuedAt: DateTime.now(),
    );

    _queue.add(queuedOrder);
    await _persistQueue();

    // 1. Kick Cash Drawer if cash
    if (paymentMethod.toLowerCase() == 'cash') {
      PrinterService.instance.kickCashDrawer();
    }

    // 2. Print Thermal Offline Receipt
    try {
      final items = receiptItems ?? [];
      final receiptData = OrderReceiptData(
        orderId: '$offlineOrderId (OFFLINE)',
        orderDate: DateTime.now(),
        customerName: customerName,
        customerMobile: customerMobile,
        items: items,
        subtotal: totalAmount,
        totalAmount: totalAmount,
        paymentMethod: '$paymentMethod [OFFLINE QUEUED]',
      );

      await PrinterService.instance.printOrderReceipt(receiptData);
    } catch (e) {
      debugPrint('[OfflineOrderQueue] Receipt printing failed: $e');
    }

    lastSyncStatus.value = 'Saved offline: $offlineOrderId';
    return offlineOrderId;
  }

  /// Syncs all locally queued orders to the server sequentially
  Future<bool> syncPendingOrders() async {
    if (_queue.isEmpty || isSyncing.value) return true;

    isSyncing.value = true;
    lastSyncStatus.value = 'Syncing ${_queue.length} orders...';
    debugPrint('[OfflineOrderQueue] Starting sync for ${_queue.length} queued orders...');

    final functions = FirebaseFunctions.instance;
    final confirmOrderCallable = functions.httpsCallable('confirmOrder');

    int successCount = 0;
    final itemsToRemove = <QueuedOrder>[];

    try {
      for (final queued in List<QueuedOrder>.from(_queue)) {
        try {
          queued.retryAttempts++;
          final result = await confirmOrderCallable.call(queued.payload);

          if (result.data['success'] == true) {
            itemsToRemove.add(queued);
            successCount++;
            debugPrint('[OfflineOrderQueue] Successfully synced ${queued.offlineOrderId} -> ${result.data['orderId']}');
          } else {
            queued.lastError = result.data['error']?.toString() ?? 'Server error';
            break; // Stop loop on failure to preserve sequential ordering
          }
        } catch (e) {
          queued.lastError = e.toString();
          debugPrint('[OfflineOrderQueue] Sync failed for ${queued.offlineOrderId}: $e');
          break; // Stop loop on network exception
        }
      }

      // Remove successfully synced orders
      for (final item in itemsToRemove) {
        _queue.remove(item);
      }
      await _persistQueue();

      lastSyncStatus.value = _queue.isEmpty
          ? 'All orders synced ($successCount synced)'
          : 'Partially synced ($successCount synced, ${_queue.length} remaining)';

      return _queue.isEmpty;
    } finally {
      isSyncing.value = false;
    }
  }

  /// Clear the queue (for administrative or testing purposes)
  Future<void> clearQueue() async {
    _queue.clear();
    await _persistQueue();
  }
}
