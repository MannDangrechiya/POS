import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'esc_pos_generator.dart';
import 'terminal_service.dart';
import '../../data/models/shift_model.dart';
import '../../data/models/refund_model.dart';

/// Connection type for thermal POS printer
enum PrinterConnectionType {
  network, // Direct TCP Socket (Port 9100)
  system,  // Operating System spooler / Bluetooth / USB via printing package
  virtual, // Development / Simulator mode (captures receipt text)
}

/// Structured item data for receipt printing
class ReceiptItemData {
  final String name;
  final double quantity;
  final String unit;
  final double price;
  final double total;

  const ReceiptItemData({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.price,
    required this.total,
  });
}

/// Structured receipt data for thermal printing
class OrderReceiptData {
  final String shopName;
  final String shopAddress;
  final String shopPhone;
  final String shopGst;
  final String orderId;
  final String? terminalId;
  final DateTime orderDate;
  final String customerName;
  final String customerMobile;
  final List<ReceiptItemData> items;
  final double subtotal;
  final double taxAmount;
  final double discountAmount;
  final double totalAmount;
  final String paymentMethod;
  final double? cashTendered;
  final double? changeReturned;

  const OrderReceiptData({
    this.shopName = 'Fruit POS Store',
    this.shopAddress = '123 Market Yard',
    this.shopPhone = '',
    this.shopGst = '',
    required this.orderId,
    this.terminalId,
    required this.orderDate,
    required this.customerName,
    required this.customerMobile,
    required this.items,
    required this.subtotal,
    this.taxAmount = 0.0,
    this.discountAmount = 0.0,
    required this.totalAmount,
    required this.paymentMethod,
    this.cashTendered,
    this.changeReturned,
  });
}

/// Hardware Thermal Printer & Cash Drawer Management Service.
///
/// Supports direct ESC/POS network streaming (TCP port 9100), OS printer spooling,
/// automatic cash drawer kick pulses, and virtual simulation for testing.
class PrinterService extends GetxService {
  static PrinterService get instance => Get.isRegistered<PrinterService>()
      ? Get.find<PrinterService>()
      : Get.put(PrinterService());

  // Configuration observables
  final Rx<PrinterConnectionType> connectionType = PrinterConnectionType.virtual.obs;
  final RxString printerIp = '192.168.1.100'.obs;
  final RxInt printerPort = 9100.obs;
  final Rx<EscPosPaperSize> paperSize = EscPosPaperSize.mm80.obs;
  final RxBool autoCut = true.obs;
  final RxBool autoKickDrawerOnCash = true.obs;
  final RxInt drawerPin = 2.obs; // Pin 2 (standard) or Pin 5
  final RxBool drawerRequiresPin = true.obs;
  final RxString managerPin = '1234'.obs;

  // Status & Telemetry
  final RxBool isPrinting = false.obs;
  final RxString lastStatus = 'Ready'.obs;
  final RxString lastReceiptText = ''.obs;
  final RxList<String> telemetryLogs = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadSettings();
  }

  /// Load persisted printer settings from SharedPreferences
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final typeStr = prefs.getString('hw_printer_type') ?? 'virtual';
      connectionType.value = PrinterConnectionType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => PrinterConnectionType.virtual,
      );

      printerIp.value = prefs.getString('hw_printer_ip') ?? '192.168.1.100';
      printerPort.value = prefs.getInt('hw_printer_port') ?? 9100;

      final paperStr = prefs.getString('hw_printer_paper') ?? '80mm';
      paperSize.value = (paperStr == '58mm')
          ? EscPosPaperSize.mm58
          : EscPosPaperSize.mm80;

      autoCut.value = prefs.getBool('hw_printer_autocut') ?? true;
      autoKickDrawerOnCash.value = prefs.getBool('hw_printer_autodrawer') ?? true;
      drawerPin.value = prefs.getInt('hw_drawer_pin') ?? 2;
      drawerRequiresPin.value = prefs.getBool('hw_drawer_req_pin') ?? true;
      managerPin.value = prefs.getString('hw_drawer_manager_pin') ?? '1234';

      _log('Hardware settings loaded: ${connectionType.value.name}, IP: ${printerIp.value}:${printerPort.value}');
    } catch (e) {
      _log('Failed to load hardware settings: $e');
    }
  }

  /// Save hardware settings
  Future<void> saveSettings({
    required PrinterConnectionType type,
    required String ip,
    required int port,
    required EscPosPaperSize paper,
    required bool cut,
    required bool autoDrawer,
    required int pin,
    required bool reqPin,
    required String mPin,
  }) async {
    connectionType.value = type;
    printerIp.value = ip.trim();
    printerPort.value = port;
    paperSize.value = paper;
    autoCut.value = cut;
    autoKickDrawerOnCash.value = autoDrawer;
    drawerPin.value = pin;
    drawerRequiresPin.value = reqPin;
    managerPin.value = mPin.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hw_printer_type', type.name);
      await prefs.setString('hw_printer_ip', ip.trim());
      await prefs.setInt('hw_printer_port', port);
      await prefs.setString('hw_printer_paper', paper == EscPosPaperSize.mm58 ? '58mm' : '80mm');
      await prefs.setBool('hw_printer_autocut', cut);
      await prefs.setBool('hw_printer_autodrawer', autoDrawer);
      await prefs.setInt('hw_drawer_pin', pin);
      await prefs.setBool('hw_drawer_req_pin', reqPin);
      await prefs.setString('hw_drawer_manager_pin', mPin.trim());

      _log('Settings saved: ${type.name} -> $ip:$port');
    } catch (e) {
      _log('Error saving hardware settings: $e');
    }
  }

  /// Formats and dispatches a customer order receipt
  Future<bool> printOrderReceipt(OrderReceiptData data) async {
    isPrinting.value = true;
    lastStatus.value = 'Printing receipt...';

    try {
      // 1. Build human-readable representation for telemetry and virtual display
      final buffer = StringBuffer();
      final regId = data.terminalId ?? (Get.isRegistered<TerminalService>() ? TerminalService.instance.terminalId.value : 'REG-01');
      buffer.writeln('================================');
      buffer.writeln('         ${data.shopName}');
      if (data.shopAddress.isNotEmpty) buffer.writeln('     ${data.shopAddress}');
      if (data.shopGst.isNotEmpty) buffer.writeln('     GSTIN: ${data.shopGst}');
      buffer.writeln('--------------------------------');
      buffer.writeln('Order ID : ${data.orderId}');
      buffer.writeln('Register : $regId');
      buffer.writeln('Date     : ${_formatDate(data.orderDate)}');
      buffer.writeln('Customer : ${data.customerName}');
      buffer.writeln('Mobile   : ${data.customerMobile}');
      buffer.writeln('--------------------------------');
      buffer.writeln('ITEM          QTY/RATE     TOTAL');
      buffer.writeln('--------------------------------');
      for (final item in data.items) {
        final qtyStr = '${item.quantity.toStringAsFixed(item.unit.toLowerCase() == 'kg' ? 2 : 0)}${item.unit}';
        buffer.writeln('${item.name.padRight(14).substring(0, 14)} ${qtyStr.padLeft(6)}x${item.price.toStringAsFixed(0)} Rs.${item.total.toStringAsFixed(2).padLeft(6)}');
      }
      buffer.writeln('--------------------------------');
      buffer.writeln('Subtotal    : Rs.${data.subtotal.toStringAsFixed(2)}');
      if (data.discountAmount > 0) {
        buffer.writeln('Discount    : -Rs.${data.discountAmount.toStringAsFixed(2)}');
      }
      if (data.taxAmount > 0) {
        buffer.writeln('Taxes       : Rs.${data.taxAmount.toStringAsFixed(2)}');
      }
      buffer.writeln('TOTAL DUE   : Rs.${data.totalAmount.toStringAsFixed(2)}');
      buffer.writeln('Payment     : ${data.paymentMethod.toUpperCase()}');
      if (data.cashTendered != null && data.cashTendered! > 0) {
        buffer.writeln('Cash Paid   : Rs.${data.cashTendered!.toStringAsFixed(2)}');
        buffer.writeln('Change Back : Rs.${(data.changeReturned ?? 0.0).toStringAsFixed(2)}');
      }
      buffer.writeln('================================');
      buffer.writeln('    THANK YOU! VISIT AGAIN!     ');
      buffer.writeln('================================');

      lastReceiptText.value = buffer.toString();

      // 2. Build hardware ESC/POS byte sequence
      final generator = EscPosGenerator(paperSize: paperSize.value);
      generator.reset();

      // Shop Header
      generator.text(
        data.shopName,
        align: EscPosAlign.center,
        bold: true,
        doubleWidth: true,
        doubleHeight: true,
      );
      if (data.shopAddress.isNotEmpty) {
        generator.text(data.shopAddress, align: EscPosAlign.center);
      }
      if (data.shopGst.isNotEmpty) {
        generator.text('GSTIN: ${data.shopGst}', align: EscPosAlign.center);
      }
      generator.divider(char: '=');

      // Order Info
      generator.row2('Order ID:', data.orderId);
      generator.row2('Register:', regId);
      generator.row2('Date:', _formatDate(data.orderDate));
      generator.row2('Customer:', data.customerName);
      if (data.customerMobile.isNotEmpty) {
        generator.row2('Mobile:', data.customerMobile);
      }
      generator.divider();

      // Items Table Header
      generator.row3('ITEM', 'QTY/RATE', 'TOTAL', bold: true);
      generator.divider();

      // Item Rows
      for (final item in data.items) {
        final qtyStr = '${item.quantity.toStringAsFixed(item.unit.toLowerCase() == 'kg' ? 2 : 0)}${item.unit}';
        final rateStr = '$qtyStr x ${item.price.toStringAsFixed(0)}';
        generator.row3(item.name, rateStr, 'Rs.${item.total.toStringAsFixed(2)}');
      }
      generator.divider();

      // Totals
      generator.row2('Subtotal:', 'Rs.${data.subtotal.toStringAsFixed(2)}');
      if (data.discountAmount > 0) {
        generator.row2('Discount:', '-Rs.${data.discountAmount.toStringAsFixed(2)}');
      }
      if (data.taxAmount > 0) {
        generator.row2('Taxes:', 'Rs.${data.taxAmount.toStringAsFixed(2)}');
      }
      generator.row2(
        'TOTAL AMOUNT:',
        'Rs.${data.totalAmount.toStringAsFixed(2)}',
        bold: true,
        doubleHeight: true,
      );
      generator.divider();

      // Payment Details
      generator.row2('Payment:', data.paymentMethod.toUpperCase(), bold: true);
      if (data.cashTendered != null && data.cashTendered! > 0) {
        generator.row2('Cash Tendered:', 'Rs.${data.cashTendered!.toStringAsFixed(2)}');
        generator.row2('Change Back:', 'Rs.${(data.changeReturned ?? 0.0).toStringAsFixed(2)}');
      }

      generator.divider(char: '=');
      generator.text('THANK YOU FOR YOUR VISIT!', align: EscPosAlign.center, bold: true);
      generator.text('Fresh Quality Guaranteed', align: EscPosAlign.center);

      // Auto cash drawer kick on cash sale
      if (autoKickDrawerOnCash.value && data.paymentMethod.toLowerCase() == 'cash') {
        generator.openCashDrawer(pin: drawerPin.value);
        _log('Auto drawer kick dispatched for cash order ${data.orderId}');
      }

      // Paper Cut
      if (autoCut.value) {
        generator.cut(partial: true);
      } else {
        generator.lineFeed(4);
      }

      final rawBytes = generator.toBytes();

      // 3. Dispatch to configured hardware target
      bool success = false;
      switch (connectionType.value) {
        case PrinterConnectionType.network:
          success = await _sendNetworkBytes(rawBytes);
          break;
        case PrinterConnectionType.system:
          success = await _sendSystemPrint(data);
          break;
        case PrinterConnectionType.virtual:
          success = true;
          _log('Virtual receipt logged for order ${data.orderId} (${rawBytes.length} bytes)');
          break;
      }

      lastStatus.value = success ? 'Receipt printed successfully' : 'Print failed';
      return success;
    } catch (e) {
      lastStatus.value = 'Print error: $e';
      _log('Print failed with exception: $e');
      return false;
    } finally {
      isPrinting.value = false;
    }
  }

  /// Sends a hardware drawer kick pulse
  Future<bool> kickCashDrawer({String? managerPinInput}) async {
    if (drawerRequiresPin.value) {
      if (managerPinInput != managerPin.value) {
        lastStatus.value = 'Invalid Manager PIN for cash drawer';
        _log('Cash drawer kick rejected: invalid manager PIN');
        return false;
      }
    }

    try {
      final generator = EscPosGenerator();
      generator.openCashDrawer(pin: drawerPin.value);
      final bytes = generator.toBytes();

      if (connectionType.value == PrinterConnectionType.network) {
        final success = await _sendNetworkBytes(bytes);
        lastStatus.value = success ? 'Cash drawer popped' : 'Drawer kick failed';
        return success;
      } else {
        _log('Virtual cash drawer kick pulse triggered (pin ${drawerPin.value})');
        lastStatus.value = 'Cash drawer popped (Virtual)';
        return true;
      }
    } catch (e) {
      lastStatus.value = 'Drawer error: $e';
      return false;
    }
  }

  /// Prints a hardware test diagnostic ticket
  Future<bool> testPrint() async {
    isPrinting.value = true;
    lastStatus.value = 'Printing test ticket...';

    try {
      final generator = EscPosGenerator(paperSize: paperSize.value);
      generator.reset();
      generator.text(
        'HARDWARE TEST TICKET',
        align: EscPosAlign.center,
        bold: true,
        doubleHeight: true,
      );
      generator.divider(char: '=');
      generator.row2('Printer Type:', connectionType.value.name.toUpperCase());
      generator.row2('IP Address:', '${printerIp.value}:${printerPort.value}');
      generator.row2('Paper Width:', paperSize.value == EscPosPaperSize.mm58 ? '58mm (32 col)' : '80mm (48 col)');
      generator.row2('Auto Cut:', autoCut.value ? 'Enabled' : 'Disabled');
      generator.row2('Drawer Kick:', autoKickDrawerOnCash.value ? 'Enabled' : 'Disabled');
      generator.row2('Test Time:', _formatDate(DateTime.now()));
      generator.divider();
      generator.text('0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ', align: EscPosAlign.center);
      generator.divider(char: '=');
      generator.text('TEST PRINT COMPLETED OK', align: EscPosAlign.center, bold: true);
      if (autoCut.value) {
        generator.cut(partial: true);
      } else {
        generator.lineFeed(4);
      }

      final bytes = generator.toBytes();
      if (connectionType.value == PrinterConnectionType.network) {
        return await _sendNetworkBytes(bytes);
      } else {
        lastReceiptText.value = '=== HARDWARE TEST TICKET OK ===\nMode: ${connectionType.value.name}\nPaper: ${paperSize.value.name}';
        _log('Virtual test ticket printed successfully');
        lastStatus.value = 'Test ticket verified';
        return true;
      }
    } catch (e) {
      lastStatus.value = 'Test print error: $e';
      return false;
    } finally {
      isPrinting.value = false;
    }
  }

  /// Prints an end-of-shift Blind Drawer Count & Z-Report audit ticket
  Future<bool> printZReport(
    ShiftModel shift, {
    String shopName = 'Fruit POS Store',
    String shopAddress = 'Market Yard POS Terminal',
  }) async {
    isPrinting.value = true;
    lastStatus.value = 'Printing Z-Report...';

    try {
      final generator = EscPosGenerator(paperSize: paperSize.value);
      generator.reset();

      // Store Header
      generator.text(
        shopName.toUpperCase(),
        align: EscPosAlign.center,
        bold: true,
        doubleHeight: true,
      );
      if (shopAddress.isNotEmpty) {
        generator.text(shopAddress, align: EscPosAlign.center);
      }
      generator.lineFeed();
      generator.text('*** Z-REPORT / SHIFT AUDIT ***', align: EscPosAlign.center, bold: true);
      generator.divider(char: '=');

      // Shift Metadata
      final displayId = shift.shiftId.length > 12 ? shift.shiftId.substring(0, 12) : shift.shiftId;
      final termId = shift.terminalId.isNotEmpty
          ? shift.terminalId
          : (Get.isRegistered<TerminalService>() ? TerminalService.instance.terminalId.value : 'REG-01');
      generator.row2('Shift ID:', displayId);
      generator.row2('Register:', termId);
      generator.row2('Cashier:', shift.cashierName);
      generator.row2('Opened:', _formatDate(shift.openedAt));
      generator.row2('Closed:', _formatDate(shift.closedAt ?? DateTime.now()));
      generator.divider();

      // Sales Summary
      generator.text('SALES SUMMARY', bold: true);
      generator.row2('Cash Sales:', 'Rs.${shift.cashSales.toStringAsFixed(2)}');
      generator.row2('UPI Sales:', 'Rs.${shift.upiSales.toStringAsFixed(2)}');
      generator.row2('Card Sales:', 'Rs.${shift.cardSales.toStringAsFixed(2)}');
      generator.row2('Order Count:', '${shift.orderCount}');
      generator.row2('GROSS SALES:', 'Rs.${shift.grossSales.toStringAsFixed(2)}', bold: true);
      generator.divider();

      // Drawer Movements (Cash In / Out)
      generator.text('DRAWER RECONCILIATION', bold: true);
      generator.row2('Opening Float:', 'Rs.${shift.openingFloat.toStringAsFixed(2)}');
      generator.row2('+ Cash Sales:', 'Rs.${shift.cashSales.toStringAsFixed(2)}');
      generator.row2('+ Cash In (Float):', 'Rs.${shift.cashInTotal.toStringAsFixed(2)}');
      generator.row2('- Cash Out (Paid):', 'Rs.${shift.cashOutTotal.toStringAsFixed(2)}');
      generator.row2('EXPECTED DRAWER:', 'Rs.${shift.expectedCash.toStringAsFixed(2)}', bold: true);
      generator.divider();

      // Blind Count Comparison
      final actual = shift.actualCashCounted ?? 0.0;
      generator.row2('ACTUAL COUNTED:', 'Rs.${actual.toStringAsFixed(2)}', bold: true, doubleHeight: true);

      final diff = shift.difference ?? (actual - shift.expectedCash);
      final tag = diff == 0 ? '[BALANCED]' : (diff > 0 ? '[OVERAGE]' : '[SHORTAGE]');
      generator.row2('VARIANCE $tag:', '${diff >= 0 ? '+' : '-'}Rs.${diff.abs().toStringAsFixed(2)}', bold: true);
      generator.divider(char: '=');

      // Individual Cash In/Out movements
      if (shift.movements.isNotEmpty) {
        generator.text('DRAWER MOVEMENTS:', bold: true);
        for (final m in shift.movements) {
          final prefix = m.type == 'cash_in' ? '+IN' : '-OUT';
          generator.row2('$prefix: ${m.reason}', 'Rs.${m.amount.toStringAsFixed(2)}');
        }
        generator.divider();
      }

      // Notes
      if (shift.notes.isNotEmpty) {
        generator.text('Notes: ${shift.notes}');
        generator.divider();
      }

      // Signature Blocks
      generator.lineFeed(2);
      generator.row2('Cashier Sign', 'Manager Sign');
      generator.divider(char: '-');
      generator.text('*** END OF SHIFT AUDIT ***', align: EscPosAlign.center, bold: true);

      // Auto Cut
      if (autoCut.value) {
        generator.cut(partial: true);
      } else {
        generator.lineFeed(4);
      }

      final rawBytes = generator.toBytes();

      // Render Virtual Text for inspection/history
      final textBuf = StringBuffer();
      textBuf.writeln('=== Z-REPORT / SHIFT AUDIT ===');
      textBuf.writeln('Shift: $displayId | Cashier: ${shift.cashierName}');
      textBuf.writeln('Gross Sales: Rs.${shift.grossSales.toStringAsFixed(2)} (${shift.orderCount} orders)');
      textBuf.writeln('Opening Float: Rs.${shift.openingFloat.toStringAsFixed(2)}');
      textBuf.writeln('Expected Cash: Rs.${shift.expectedCash.toStringAsFixed(2)}');
      textBuf.writeln('Actual Counted: Rs.${actual.toStringAsFixed(2)}');
      textBuf.writeln('Variance: ${diff >= 0 ? '+' : '-'}Rs.${diff.abs().toStringAsFixed(2)} $tag');
      lastReceiptText.value = textBuf.toString();

      bool success = false;
      if (connectionType.value == PrinterConnectionType.network) {
        success = await _sendNetworkBytes(rawBytes);
      } else {
        _log('Virtual Z-Report generated for shift $displayId');
        success = true;
      }

      lastStatus.value = success ? 'Z-Report printed' : 'Z-Report print failed';
      return success;
    } catch (e) {
      lastStatus.value = 'Z-Report error: $e';
      _log('Z-Report printing failed: $e');
      return false;
    } finally {
      isPrinting.value = false;
    }
  }

  /// Prints an itemized Customer Return & Refund ticket
  Future<bool> printRefundTicket(
    RefundModel refund, {
    String shopName = 'Fruit POS Store',
    String shopAddress = '',
  }) async {
    isPrinting.value = true;
    lastStatus.value = 'Printing Return/Refund ticket...';

    try {
      final generator = EscPosGenerator(paperSize: paperSize.value);
      generator.reset();

      // Store Header
      generator.text(
        shopName.toUpperCase(),
        align: EscPosAlign.center,
        bold: true,
        doubleHeight: true,
      );
      if (shopAddress.isNotEmpty) {
        generator.text(shopAddress, align: EscPosAlign.center);
      }
      generator.lineFeed();
      generator.text('*** RETURN & REFUND VOUCHER ***', align: EscPosAlign.center, bold: true);
      generator.divider(char: '=');

      // Metadata
      final refundIdDisplay = refund.refundId.length > 12 ? refund.refundId.substring(0, 12) : refund.refundId;
      final orderIdDisplay = refund.orderId.length > 12 ? refund.orderId.substring(0, 12) : refund.orderId;
      final termId = (Get.isRegistered<TerminalService>() ? TerminalService.instance.terminalId.value : 'REG-01');
      generator.row2('Refund ID:', refundIdDisplay);
      generator.row2('Original Order:', orderIdDisplay);
      generator.row2('Register:', termId);
      generator.row2('Date & Time:', _formatDate(refund.createdAt));
      if (refund.customerName.isNotEmpty) {
        generator.row2('Customer:', refund.customerName);
      }
      if (refund.employeeName.isNotEmpty) {
        generator.row2('Processed By:', refund.employeeName);
      }
      generator.divider();

      // Items table
      generator.row3('ITEM RETURNED', 'QTY/RATE', 'REFUND', bold: true);
      generator.divider();

      for (final item in refund.items) {
        final dispTag = item.disposition == 'damaged' ? '[DAMAGED]' : '[RESTOCK]';
        final qtyRate = '${item.quantityReturned.toStringAsFixed(2)} x Rs.${item.unitPrice.toStringAsFixed(0)}';
        generator.row3('${item.productName} $dispTag', qtyRate, 'Rs.${item.refundAmount.toStringAsFixed(2)}');
      }
      generator.divider();

      // Totals
      generator.row2(
        'TOTAL REFUNDED:',
        'Rs.${refund.totalRefundAmount.toStringAsFixed(2)}',
        bold: true,
        doubleHeight: true,
      );
      generator.row2('Refund Method:', refund.refundMethod.toUpperCase(), bold: true);
      if (refund.reason.isNotEmpty) {
        generator.row2('Reason:', refund.reason);
      }
      generator.divider(char: '=');

      // Drawer kick if cash refund
      if (autoKickDrawerOnCash.value && refund.refundMethod.toLowerCase() == 'cash') {
        generator.openCashDrawer(pin: drawerPin.value);
        _log('Auto drawer kick dispatched for cash refund ${refund.refundId}');
      }

      // Signatures
      generator.lineFeed(2);
      generator.row2('Customer Sign', 'Cashier Sign');
      generator.divider(char: '-');
      generator.text('Fresh Fruit Quality Guaranteed', align: EscPosAlign.center);

      if (autoCut.value) {
        generator.cut(partial: true);
      } else {
        generator.lineFeed(4);
      }

      final rawBytes = generator.toBytes();

      // Virtual Text Preview
      final textBuf = StringBuffer();
      textBuf.writeln('=== RETURN & REFUND VOUCHER ===');
      textBuf.writeln('Refund: $refundIdDisplay | Order: $orderIdDisplay');
      textBuf.writeln('Total Refunded: Rs.${refund.totalRefundAmount.toStringAsFixed(2)} (${refund.refundMethod.toUpperCase()})');
      for (final i in refund.items) {
        textBuf.writeln('- ${i.productName}: ${i.quantityReturned} (${i.disposition.toUpperCase()}) = Rs.${i.refundAmount.toStringAsFixed(2)}');
      }
      lastReceiptText.value = textBuf.toString();

      bool success = false;
      if (connectionType.value == PrinterConnectionType.network) {
        success = await _sendNetworkBytes(rawBytes);
      } else {
        _log('Virtual Return/Refund ticket printed for $refundIdDisplay');
        success = true;
      }

      lastStatus.value = success ? 'Refund ticket printed' : 'Refund ticket print failed';
      return success;
    } catch (e) {
      lastStatus.value = 'Refund print error: $e';
      _log('Refund ticket print failed: $e');
      return false;
    } finally {
      isPrinting.value = false;
    }
  }

  /// Prints a thermal Customer Khata / Udhar settlement receipt
  Future<bool> printCreditSettlementReceipt({
    required String receiptId,
    required String customerName,
    required String customerMobile,
    required double previousBalance,
    required double amountPaid,
    required double remainingBalance,
    required String paymentMethod,
    String shopName = 'Fruit POS Store',
    String shopAddress = '',
  }) async {
    isPrinting.value = true;
    lastStatus.value = 'Printing Credit Settlement receipt...';

    try {
      final generator = EscPosGenerator(paperSize: paperSize.value);
      generator.reset();

      // Store Header
      generator.text(
        shopName.toUpperCase(),
        align: EscPosAlign.center,
        bold: true,
        doubleHeight: true,
      );
      if (shopAddress.isNotEmpty) {
        generator.text(shopAddress, align: EscPosAlign.center);
      }
      generator.lineFeed();
      generator.text('*** KHATA / CREDIT PAYMENT ***', align: EscPosAlign.center, bold: true);
      generator.divider(char: '=');

      final displayId = receiptId.length > 12 ? receiptId.substring(0, 12) : receiptId;
      final termId = (Get.isRegistered<TerminalService>() ? TerminalService.instance.terminalId.value : 'REG-01');
      generator.row2('Receipt ID:', displayId);
      generator.row2('Register:', termId);
      generator.row2('Date:', _formatDate(DateTime.now()));
      generator.row2('Customer:', customerName);
      generator.row2('Mobile:', customerMobile);
      generator.row2('Mode:', paymentMethod.toUpperCase());
      generator.divider();

      // Balances
      generator.row2('Previous Due:', 'Rs.${previousBalance.toStringAsFixed(2)}');
      generator.row2('AMOUNT PAID:', 'Rs.${amountPaid.toStringAsFixed(2)}', bold: true, doubleHeight: true);
      generator.row2('REMAINING BALANCE:', 'Rs.${remainingBalance.toStringAsFixed(2)}', bold: true);
      generator.divider(char: '=');

      generator.lineFeed(2);
      generator.row2('Customer Sign', 'Cashier Sign');
      generator.divider(char: '-');
      generator.text('Thank you for your business!', align: EscPosAlign.center, bold: true);

      // Auto kick cash drawer if paymentMethod is cash
      if (paymentMethod.toLowerCase() == 'cash' && autoKickDrawerOnCash.value) {
        generator.openCashDrawer(pin: 2);
      }

      // Auto Cut
      if (autoCut.value) {
        generator.cut(partial: true);
      } else {
        generator.lineFeed(4);
      }

      final rawBytes = generator.toBytes();

      // Virtual Text Preview
      final textBuf = StringBuffer();
      textBuf.writeln('=== KHATA PAYMENT RECEIPT ===');
      textBuf.writeln('Receipt: $displayId | Register: $termId | Customer: $customerName');
      textBuf.writeln('Previous Due: Rs.${previousBalance.toStringAsFixed(2)}');
      textBuf.writeln('Amount Paid: Rs.${amountPaid.toStringAsFixed(2)} (${paymentMethod.toUpperCase()})');
      textBuf.writeln('Remaining Balance: Rs.${remainingBalance.toStringAsFixed(2)}');
      lastReceiptText.value = textBuf.toString();

      bool success = false;
      if (connectionType.value == PrinterConnectionType.network) {
        success = await _sendNetworkBytes(rawBytes);
      } else {
        _log('Virtual Credit Settlement receipt printed for $displayId');
        success = true;
      }

      lastStatus.value = success ? 'Settlement receipt printed' : 'Settlement receipt print failed';
      return success;
    } catch (e) {
      lastStatus.value = 'Settlement print error: $e';
      _log('Settlement print failed: $e');
      return false;
    } finally {
      isPrinting.value = false;
    }
  }

  /// Prints an adhesive thermal barcode label for fruit punnets, pre-packed produce, or wholesale boxes
  Future<bool> printProductLabel({
    required String productName,
    required double price,
    double? weightKg,
    String? unit,
    String? barcode,
    String? packDate,
    String? bestBefore,
    String shopName = 'Fresh Fruit Mart',
    int copies = 1,
  }) async {
    isPrinting.value = true;
    lastStatus.value = 'Printing product barcode label...';

    try {
      final codeToPrint = (barcode != null && barcode.isNotEmpty)
          ? barcode
          : '20${DateTime.now().millisecondsSinceEpoch.toString().substring(5, 13)}';
      final formattedPack = packDate ?? _formatDate(DateTime.now());
      final formattedExp = bestBefore ?? _formatDate(DateTime.now().add(const Duration(days: 3)));
      final u = unit ?? (weightKg != null ? 'kg' : 'pc');

      // Virtual Text Preview
      final labelBuf = StringBuffer();
      labelBuf.writeln('========== PRODUCT LABEL ==========');
      labelBuf.writeln(shopName);
      labelBuf.writeln(productName.toUpperCase());
      if (weightKg != null) {
        labelBuf.writeln('NET WEIGHT: ${weightKg.toStringAsFixed(3)} $u');
      }
      labelBuf.writeln('PRICE: Rs.${price.toStringAsFixed(2)}');
      labelBuf.writeln('PACKED: $formattedPack | EXP: $formattedExp');
      labelBuf.writeln('BARCODE: $codeToPrint');
      labelBuf.writeln('===================================');
      lastReceiptText.value = labelBuf.toString();

      for (int c = 0; c < copies; c++) {
        final generator = EscPosGenerator(paperSize: paperSize.value);
        generator.reset();

        // 1. Store Header
        generator.text(shopName, align: EscPosAlign.center, bold: true);
        generator.divider(char: '-');

        // 2. Product Name (Bold & Large)
        generator.text(
          productName.toUpperCase(),
          align: EscPosAlign.center,
          bold: true,
          doubleHeight: true,
        );

        // 3. Weight / Measurement
        if (weightKg != null) {
          generator.row2('NET WEIGHT:', '${weightKg.toStringAsFixed(3)} $u', bold: true);
        } else {
          generator.row2('UNIT:', '1 $u', bold: true);
        }

        // 4. Dates
        generator.row2('Packed:', formattedPack);
        generator.row2('Best Before:', formattedExp);
        generator.divider(char: '=');

        // 5. Price Display
        generator.text(
          'MRP: Rs.${price.toStringAsFixed(2)}',
          align: EscPosAlign.center,
          bold: true,
          doubleWidth: true,
          doubleHeight: true,
        );
        generator.text('(Inclusive of all taxes)', align: EscPosAlign.center);
        generator.lineFeed();

        // 6. 1D Barcode (Code128)
        generator.barcode128(codeToPrint, height: 60, width: 2, showHri: true);

        // 7. Cut or Feed
        if (autoCut.value) {
          generator.cut(partial: true);
        } else {
          generator.lineFeed(3);
        }

        final rawBytes = generator.toBytes();

        if (connectionType.value == PrinterConnectionType.network) {
          await _sendNetworkBytes(rawBytes);
        } else {
          _log('Virtual label printed for $productName ($codeToPrint)');
        }
      }

      lastStatus.value = 'Label printed successfully';
      return true;
    } catch (e) {
      lastStatus.value = 'Label print error: $e';
      _log('Product label print error: $e');
      return false;
    } finally {
      isPrinting.value = false;
    }
  }

  /// Sends raw ESC/POS byte sequence over TCP Socket (Port 9100)
  Future<bool> _sendNetworkBytes(Uint8List bytes) async {
    Socket? socket;
    try {
      _log('Connecting to thermal printer at ${printerIp.value}:${printerPort.value}...');
      socket = await Socket.connect(
        printerIp.value,
        printerPort.value,
        timeout: const Duration(seconds: 4),
      );

      socket.add(bytes);
      await socket.flush();
      await socket.close();
      _log('Sent ${bytes.length} bytes to thermal printer successfully');
      return true;
    } catch (e) {
      _log('Thermal printer network error: $e');
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Prints via OS printing raster / spooler using standard thermal page roll
  Future<bool> _sendSystemPrint(OrderReceiptData data) async {
    try {
      final doc = pw.Document();
      final rollWidth = (paperSize.value == EscPosPaperSize.mm58) ? 58.0 * PdfPageFormat.mm : 80.0 * PdfPageFormat.mm;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(rollWidth, double.infinity, marginAll: 4 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    data.shopName,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                  ),
                ),
                pw.Divider(thickness: 1),
                pw.Text('Order ID: ${data.orderId}', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Date: ${_formatDate(data.orderDate)}', style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Customer: ${data.customerName}', style: const pw.TextStyle(fontSize: 9)),
                pw.Divider(thickness: 0.5),
                ...data.items.map((item) => pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${item.name} (${item.quantity} ${item.unit})', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Rs.${item.total.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    )),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL DUE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text('Rs.${data.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Center(child: pw.Text('Thank you! Visit again!', style: const pw.TextStyle(fontSize: 8))),
              ],
            );
          },
        ),
      );

      final pdfBytes = await doc.save();
      return await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: 'receipt_${data.orderId}',
      );
    } catch (e) {
      _log('System print failed: $e');
      return false;
    }
  }

  void _log(String message) {
    debugPrint('[PrinterService] $message');
    telemetryLogs.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $message');
    if (telemetryLogs.length > 50) telemetryLogs.removeLast();
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
