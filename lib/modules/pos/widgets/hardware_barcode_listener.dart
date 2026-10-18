import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intercepts hardware barcode scanner keystrokes (USB/Bluetooth HID wedge scanners).
/// Handheld barcode scanners emulate physical keyboards by typing characters
/// rapidly (typically <40ms between characters) followed by an Enter key.
class HardwareBarcodeListener extends StatefulWidget {
  final Widget child;
  final void Function(String barcode) onBarcodeScanned;
  final bool enabled;

  const HardwareBarcodeListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
    this.enabled = true,
  });

  @override
  State<HardwareBarcodeListener> createState() =>
      _HardwareBarcodeListenerState();
}

class _HardwareBarcodeListenerState extends State<HardwareBarcodeListener> {
  final StringBuffer _buffer = StringBuffer();
  DateTime _lastKeystrokeTime = DateTime.now();
  final FocusNode _focusNode = FocusNode();

  // Maximum milliseconds between keystrokes to consider it scanner input
  static const int _maxInterKeyDelayMs = 80;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!widget.enabled) return;

    if (event is! KeyDownEvent) return;

    final now = DateTime.now();
    final delay = now.difference(_lastKeystrokeTime).inMilliseconds;
    _lastKeystrokeTime = now;

    // If typing was too slow, clear previous buffer (it was human typing, not a scanner)
    if (delay > _maxInterKeyDelayMs && _buffer.isNotEmpty) {
      _buffer.clear();
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString().trim();
      _buffer.clear();
      if (code.length >= 3) {
        widget.onBarcodeScanned(code);
      }
      return;
    }

    // Capture printable characters
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        character.codeUnitAt(0) >= 32) {
      _buffer.write(character);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
