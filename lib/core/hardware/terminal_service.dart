import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages physical POS checkout terminal & register configuration.
///
/// Supports multi-terminal stores where multiple registers (e.g. Counter 1,
/// Counter 2, Wholesale Desk, Express Lane) operate in parallel within the same shop.
class TerminalService extends GetxService {
  static TerminalService get instance => Get.isRegistered<TerminalService>()
      ? Get.find<TerminalService>()
      : Get.put(TerminalService());

  static const String prefTerminalId = 'pos_terminal_id';
  static const String prefTerminalName = 'pos_terminal_name';
  static const String prefBranchCode = 'pos_branch_code';

  final RxString terminalId = 'REG-01'.obs;
  final RxString terminalName = 'Counter 1 (Main Till)'.obs;
  final RxString branchCode = 'MAIN'.obs;
  final RxBool isLoaded = false.obs;

  Future<void>? _loadingFuture;

  @override
  void onInit() {
    super.onInit();
    loadSettings();
  }

  /// Load terminal identity from local storage
  Future<void> loadSettings() async {
    if (_loadingFuture != null) return _loadingFuture;
    _loadingFuture = _doLoadSettings();
    return _loadingFuture;
  }

  Future<void> _doLoadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      terminalId.value = prefs.getString(prefTerminalId) ?? 'REG-01';
      terminalName.value = prefs.getString(prefTerminalName) ?? 'Counter 1 (Main Till)';
      branchCode.value = prefs.getString(prefBranchCode) ?? 'MAIN';
      isLoaded.value = true;
      debugPrint('[TerminalService] Terminal initialized: ${terminalId.value} (${terminalName.value})');
    } catch (e) {
      debugPrint('[TerminalService] Error loading terminal settings: $e');
    }
  }

  /// Persist terminal identity
  Future<void> saveSettings({
    required String id,
    required String name,
    String? branch,
  }) async {
    if (_loadingFuture != null) {
      await _loadingFuture;
    }
    terminalId.value = id.trim().toUpperCase();
    terminalName.value = name.trim();
    if (branch != null) branchCode.value = branch.trim().toUpperCase();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefTerminalId, terminalId.value);
      await prefs.setString(prefTerminalName, terminalName.value);
      await prefs.setString(prefBranchCode, branchCode.value);
      debugPrint('[TerminalService] Terminal settings persisted: ${terminalId.value}');
    } catch (e) {
      debugPrint('[TerminalService] Error saving terminal settings: $e');
    }
  }
}
