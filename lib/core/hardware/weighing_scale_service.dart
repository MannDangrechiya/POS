import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Operating modes for digital weighing scale
enum ScaleMode {
  simulator, // Realistic simulator with jitter & stabilization
  network,   // TCP Socket connection to Network/Serial scale (e.g. CAS, Essae, Toledo)
  manual,    // Manual entry only (scale disabled)
}

/// Digital Weighing Scale Service for real-time weight acquisition in fruit POS.
class WeighingScaleService extends GetxService {
  static WeighingScaleService get instance => Get.isRegistered<WeighingScaleService>()
      ? Get.find<WeighingScaleService>()
      : Get.put(WeighingScaleService());

  // Observables
  final Rx<ScaleMode> scaleMode = ScaleMode.simulator.obs;
  final RxString scaleIp = '192.168.1.150'.obs;
  final RxInt scalePort = 4001.obs;

  final RxDouble currentWeight = 0.0.obs;
  final RxDouble tareWeight = 0.0.obs;
  final RxBool isStable = true.obs;
  final RxBool isConnected = false.obs;
  final RxString unit = 'kg'.obs;
  final RxString rawData = ''.obs;

  Socket? _networkSocket;
  StreamSubscription? _socketSubscription;
  Timer? _simulatorTimer;
  double _targetSimulatedWeight = 1.250;
  final Random _random = Random();

  @override
  void onInit() {
    super.onInit();
    loadSettings();
  }

  @override
  void onClose() {
    disconnect();
    super.onClose();
  }

  /// Load persisted scale settings
  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString('hw_scale_mode') ?? 'simulator';
      scaleMode.value = ScaleMode.values.firstWhere(
        (e) => e.name == modeStr,
        orElse: () => ScaleMode.simulator,
      );
      scaleIp.value = prefs.getString('hw_scale_ip') ?? '192.168.1.150';
      scalePort.value = prefs.getInt('hw_scale_port') ?? 4001;

      connect();
    } catch (e) {
      debugPrint('[ScaleService] Error loading settings: $e');
    }
  }

  /// Save scale settings
  Future<void> saveSettings({
    required ScaleMode mode,
    required String ip,
    required int port,
  }) async {
    scaleMode.value = mode;
    scaleIp.value = ip.trim();
    scalePort.value = port;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hw_scale_mode', mode.name);
      await prefs.setString('hw_scale_ip', ip.trim());
      await prefs.setInt('hw_scale_port', port);
    } catch (e) {
      debugPrint('[ScaleService] Error saving settings: $e');
    }

    // Reconnect with new configuration
    await disconnect();
    await connect();
  }

  /// Connect or start scale service based on active mode
  Future<void> connect() async {
    if (scaleMode.value == ScaleMode.manual) {
      isConnected.value = false;
      return;
    }

    if (scaleMode.value == ScaleMode.simulator) {
      _startSimulator();
      isConnected.value = true;
      return;
    }

    if (scaleMode.value == ScaleMode.network) {
      await _connectNetworkScale();
    }
  }

  /// Disconnect socket / stop simulator
  Future<void> disconnect() async {
    _simulatorTimer?.cancel();
    _simulatorTimer = null;

    await _socketSubscription?.cancel();
    _socketSubscription = null;

    _networkSocket?.destroy();
    _networkSocket = null;

    isConnected.value = false;
  }

  /// Tare current weight (sets current container as zero reference)
  void tare() {
    tareWeight.value = currentWeight.value + tareWeight.value;
    currentWeight.value = 0.0;
  }

  /// Zero scale reading
  void zero() {
    tareWeight.value = 0.0;
    currentWeight.value = 0.0;
    _targetSimulatedWeight = 0.0;
  }

  /// Manually inject simulated weight for testing
  void setSimulatedWeight(double weight) {
    _targetSimulatedWeight = max(0.0, weight);
    isStable.value = false;
  }

  /// Starts the realistic weighing scale simulator
  void _startSimulator() {
    _simulatorTimer?.cancel();
    // Updates reading every 200ms with realistic damping towards target weight
    _simulatorTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_targetSimulatedWeight <= 0) {
        currentWeight.value = 0.0;
        isStable.value = true;
        return;
      }

      final diff = _targetSimulatedWeight - currentWeight.value;
      if (diff.abs() < 0.005) {
        currentWeight.value = _targetSimulatedWeight;
        isStable.value = true;
      } else {
        // Step closer with small noise
        final step = diff * 0.35 + (_random.nextDouble() - 0.5) * 0.01;
        currentWeight.value = double.parse((currentWeight.value + step).toStringAsFixed(3));
        isStable.value = false;
      }
    });
  }

  /// Connects to a physical TCP/Serial Ethernet scale
  Future<void> _connectNetworkScale() async {
    try {
      _networkSocket = await Socket.connect(
        scaleIp.value,
        scalePort.value,
        timeout: const Duration(seconds: 4),
      );
      isConnected.value = true;

      _socketSubscription = _networkSocket!
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) => _parseScaleData(line),
        onError: (err) {
          debugPrint('[ScaleService] Scale stream error: $err');
          isConnected.value = false;
        },
        onDone: () {
          isConnected.value = false;
        },
      );
    } catch (e) {
      debugPrint('[ScaleService] Network scale connection failed: $e');
      isConnected.value = false;
    }
  }

  /// Parses ASCII stream lines from scale
  /// Examples:
  /// - Toledo / NCI: "ST,GS,+   1.250kg" -> 1.250, stable
  /// - Essae / CAS:  "W: 1.250kg" -> 1.250
  /// - Plain decimal: "1.250"
  void _parseScaleData(String line) {
    rawData.value = line;
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    // Check stability indicator (ST = Stable, US = Unstable)
    if (trimmed.startsWith('ST')) {
      isStable.value = true;
    } else if (trimmed.startsWith('US')) {
      isStable.value = false;
    }

    // Extract numerical decimal value
    final regex = RegExp(r'[-+]?\d*\.?\d+');
    final match = regex.firstMatch(trimmed);
    if (match != null) {
      final val = double.tryParse(match.group(0) ?? '');
      if (val != null) {
        final net = max(0.0, val - tareWeight.value);
        currentWeight.value = double.parse(net.toStringAsFixed(3));
      }
    }
  }
}
