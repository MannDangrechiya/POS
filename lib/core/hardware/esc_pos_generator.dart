import 'dart:convert';
import 'dart:typed_data';

/// Text alignment in ESC/POS thermal printing
enum EscPosAlign {
  left,
  center,
  right,
}

/// Paper roll width standard
enum EscPosPaperSize {
  mm58(32), // 58mm paper: 32 columns in standard Font A
  mm80(48); // 80mm paper: 48 columns in standard Font A

  final int widthChars;
  const EscPosPaperSize(this.widthChars);
}

/// Pure Dart ESC/POS byte generator for thermal POS printers.
///
/// Converts receipts, itemized rows, dividers, barcodes, and cash drawer
/// kick commands into hardware byte streams conforming to standard ESC/POS.
class EscPosGenerator {
  final EscPosPaperSize paperSize;
  final List<int> _bytes = [];

  EscPosGenerator({this.paperSize = EscPosPaperSize.mm80});

  /// Get compiled byte stream
  Uint8List toBytes() => Uint8List.fromList(_bytes);

  /// Hardware reset / Initialize printer (ESC @)
  void reset() {
    _bytes.addAll([0x1B, 0x40]);
  }

  /// Line feed (LF)
  void lineFeed([int count = 1]) {
    for (int i = 0; i < count; i++) {
      _bytes.add(0x0A);
    }
  }

  /// Set text alignment (ESC a n)
  void setAlign(EscPosAlign align) {
    int n = 0;
    switch (align) {
      case EscPosAlign.left:
        n = 0;
        break;
      case EscPosAlign.center:
        n = 1;
        break;
      case EscPosAlign.right:
        n = 2;
        break;
    }
    _bytes.addAll([0x1B, 0x61, n]);
  }

  /// Set bold emphasis (ESC E n)
  void setBold(bool enabled) {
    _bytes.addAll([0x1B, 0x45, enabled ? 1 : 0]);
  }

  /// Set text magnification size (GS ! n)
  void setTextSize({bool doubleWidth = false, bool doubleHeight = false}) {
    int n = 0;
    if (doubleWidth) n |= 0x10;
    if (doubleHeight) n |= 0x01;
    _bytes.addAll([0x1D, 0x21, n]);
  }

  /// Print plain text line with optional styling
  void text(
    String text, {
    EscPosAlign align = EscPosAlign.left,
    bool bold = false,
    bool doubleWidth = false,
    bool doubleHeight = false,
  }) {
    if (align != EscPosAlign.left) setAlign(align);
    if (bold) setBold(true);
    if (doubleWidth || doubleHeight) {
      setTextSize(doubleWidth: doubleWidth, doubleHeight: doubleHeight);
    }

    // Encode text as latin1/ascii for thermal printer code pages
    final cleanText = _sanitizeText(text);
    _bytes.addAll(latin1.encode(cleanText));
    _bytes.add(0x0A); // LF

    // Reset styles if applied
    if (bold) setBold(false);
    if (doubleWidth || doubleHeight) setTextSize();
    if (align != EscPosAlign.left) setAlign(EscPosAlign.left);
  }

  /// Print a horizontal rule divider matching paper width
  void divider({String char = '-'}) {
    final rule = char.padRight(paperSize.widthChars, char).substring(0, paperSize.widthChars);
    text(rule, align: EscPosAlign.left);
  }

  /// Print a double-column row (Left label, Right value) justified across paper width
  void row2(
    String left,
    String right, {
    bool bold = false,
    bool doubleHeight = false,
  }) {
    final cleanLeft = _sanitizeText(left);
    final cleanRight = _sanitizeText(right);
    final totalWidth = paperSize.widthChars;

    if (cleanLeft.length + cleanRight.length >= totalWidth) {
      // If combined text overflows, truncate left or wrap
      final maxLeft = totalWidth - cleanRight.length - 1;
      final safeLeft = maxLeft > 0 ? cleanLeft.substring(0, maxLeft) : cleanLeft;
      final spaces = totalWidth - (safeLeft.length + cleanRight.length);
      final line = safeLeft + (' ' * (spaces > 0 ? spaces : 1)) + cleanRight;
      text(line, bold: bold, doubleHeight: doubleHeight);
    } else {
      final spaces = totalWidth - (cleanLeft.length + cleanRight.length);
      final line = cleanLeft + (' ' * spaces) + cleanRight;
      text(line, bold: bold, doubleHeight: doubleHeight);
    }
  }

  /// Print a 3-column row (Item description, Qty/Rate, Total)
  void row3(String col1, String col2, String col3, {bool bold = false}) {
    final clean1 = _sanitizeText(col1);
    final clean2 = _sanitizeText(col2);
    final clean3 = _sanitizeText(col3);
    final width = paperSize.widthChars;

    if (width == 32) {
      // 58mm: Column 1 takes 14 chars, Column 2 takes 9, Column 3 takes 9
      final c1 = clean1.padRight(14).substring(0, 14);
      final c2 = clean2.padLeft(9).substring(0, 9);
      final c3 = clean3.padLeft(9).substring(0, 9);
      text('$c1$c2$c3', bold: bold);
    } else {
      // 80mm: Column 1 takes 24 chars, Column 2 takes 12, Column 3 takes 12
      final c1 = clean1.padRight(24).substring(0, 24);
      final c2 = clean2.padLeft(12).substring(0, 12);
      final c3 = clean3.padLeft(12).substring(0, 12);
      text('$c1$c2$c3', bold: bold);
    }
  }

  /// Hardware pulse to open Cash Drawer (ESC p m t1 t2)
  /// pin: 2 = drawer pin 2, 5 = drawer pin 5
  void openCashDrawer({int pin = 2}) {
    final m = (pin == 2) ? 0x00 : 0x01;
    _bytes.addAll([0x1B, 0x70, m, 0x19, 0xFA]);
  }

  /// Paper cut command (GS V m)
  /// partial: true = partial cut (leaving small tab), false = full cut
  void cut({bool partial = true}) {
    lineFeed(3); // Feed paper past printhead before cutting
    _bytes.addAll([0x1D, 0x56, partial ? 0x01 : 0x00]);
  }

  /// Print a Code 128 1D barcode (GS k 73)
  /// Commonly used on fruit punnets, cartons, and weight scale price stickers.
  void barcode128(
    String data, {
    int height = 64,
    int width = 2,
    bool showHri = true,
    EscPosAlign align = EscPosAlign.center,
  }) {
    if (align != EscPosAlign.left) setAlign(align);

    // Set barcode height (GS h n)
    _bytes.addAll([0x1D, 0x68, height.clamp(1, 255)]);

    // Set module width (GS w n, 2-6)
    _bytes.addAll([0x1D, 0x77, width.clamp(2, 6)]);

    // Set HRI characters print position (GS H n: 0 = none, 2 = below)
    _bytes.addAll([0x1D, 0x48, showHri ? 2 : 0]);

    // Code 128 Function B format: [0x1D, 0x6B, 73, length, ...bytes]
    // Subset B prefix: {B (0x7B, 0x42)
    final clean = _sanitizeText(data).trim();
    final textBytes = latin1.encode(clean);
    final payload = [0x7B, 0x42, ...textBytes];

    _bytes.addAll([0x1D, 0x6B, 73, payload.length, ...payload]);
    lineFeed();

    if (align != EscPosAlign.left) setAlign(EscPosAlign.left);
  }

  /// Print a 2D QR Code using standard ESC/POS 2D symbology commands
  void qrCode(
    String content, {
    int size = 5,
    EscPosAlign align = EscPosAlign.center,
  }) {
    if (align != EscPosAlign.left) setAlign(align);

    final clean = _sanitizeText(content).trim();
    final dataBytes = latin1.encode(clean);

    // 1. Model: Model 2 (0x32)
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

    // 2. Module size (1-16)
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.clamp(1, 16)]);

    // 3. Error correction level (0x31 = Level M)
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31]);

    // 4. Store data in symbol storage area
    final pL = (dataBytes.length + 3) & 0xFF;
    final pH = ((dataBytes.length + 3) >> 8) & 0xFF;
    _bytes.addAll([0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30, ...dataBytes]);

    // 5. Print stored symbol
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    lineFeed();

    if (align != EscPosAlign.left) setAlign(EscPosAlign.left);
  }

  /// Clean non-ASCII characters (e.g. replace Rupee symbol with 'Rs.' for thermal printers)
  static String _sanitizeText(String input) {
    return input
        .replaceAll('₹', 'Rs.')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('—', '-')
        .replaceAll('–', '-');
  }
}
