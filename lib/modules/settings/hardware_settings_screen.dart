import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/hardware/esc_pos_generator.dart';
import '../../core/hardware/printer_service.dart';
import '../../core/hardware/weighing_scale_service.dart';
import '../../core/hardware/cfd_service.dart';
import '../../core/hardware/terminal_service.dart';
import '../pos/cfd/customer_facing_display_screen.dart';

/// Hardware Peripherals Setup & Diagnostic Screen.
///
/// Configures ESC/POS thermal receipt printers, cash drawer kick pulses,
/// digital weighing scale communication, and customer facing displays.
class HardwareSettingsScreen extends StatefulWidget {
  const HardwareSettingsScreen({super.key});

  @override
  State<HardwareSettingsScreen> createState() => _HardwareSettingsScreenState();
}

class _HardwareSettingsScreenState extends State<HardwareSettingsScreen> {
  final printer = PrinterService.instance;
  final scale = WeighingScaleService.instance;
  final cfd = CfdService.instance;
  final terminal = TerminalService.instance;

  late TextEditingController _terminalIdController;
  late TextEditingController _terminalNameController;
  late TextEditingController _branchCodeController;

  late TextEditingController _printerIpController;
  late TextEditingController _printerPortController;
  late TextEditingController _scaleIpController;
  late TextEditingController _scalePortController;
  late TextEditingController _managerPinController;
  late TextEditingController _storeNameController;
  late TextEditingController _simWeightController;

  PrinterConnectionType _selectedPrinterType = PrinterConnectionType.virtual;
  EscPosPaperSize _selectedPaperSize = EscPosPaperSize.mm80;
  bool _autoCut = true;
  bool _autoDrawer = true;
  int _drawerPin = 2;
  bool _reqPin = true;

  ScaleMode _selectedScaleMode = ScaleMode.simulator;

  @override
  void initState() {
    super.initState();
    _terminalIdController = TextEditingController(text: terminal.terminalId.value);
    _terminalNameController = TextEditingController(text: terminal.terminalName.value);
    _branchCodeController = TextEditingController(text: terminal.branchCode.value);

    _selectedPrinterType = printer.connectionType.value;
    _selectedPaperSize = printer.paperSize.value;
    _autoCut = printer.autoCut.value;
    _autoDrawer = printer.autoKickDrawerOnCash.value;
    _drawerPin = printer.drawerPin.value;
    _reqPin = printer.drawerRequiresPin.value;

    _printerIpController = TextEditingController(text: printer.printerIp.value);
    _printerPortController = TextEditingController(text: printer.printerPort.value.toString());
    _scaleIpController = TextEditingController(text: scale.scaleIp.value);
    _scalePortController = TextEditingController(text: scale.scalePort.value.toString());
    _managerPinController = TextEditingController(text: printer.managerPin.value);
    _storeNameController = TextEditingController(text: cfd.storeName.value);
    _simWeightController = TextEditingController(text: '1.250');

    _selectedScaleMode = scale.scaleMode.value;
  }

  @override
  void dispose() {
    _terminalIdController.dispose();
    _terminalNameController.dispose();
    _branchCodeController.dispose();
    _printerIpController.dispose();
    _printerPortController.dispose();
    _scaleIpController.dispose();
    _scalePortController.dispose();
    _managerPinController.dispose();
    _storeNameController.dispose();
    _simWeightController.dispose();
    super.dispose();
  }

  void _saveAll() async {
    await terminal.saveSettings(
      id: _terminalIdController.text,
      name: _terminalNameController.text,
      branch: _branchCodeController.text,
    );

    await printer.saveSettings(
      type: _selectedPrinterType,
      ip: _printerIpController.text,
      port: int.tryParse(_printerPortController.text) ?? 9100,
      paper: _selectedPaperSize,
      cut: _autoCut,
      autoDrawer: _autoDrawer,
      pin: _drawerPin,
      reqPin: _reqPin,
      mPin: _managerPinController.text,
    );

    await scale.saveSettings(
      mode: _selectedScaleMode,
      ip: _scaleIpController.text,
      port: int.tryParse(_scalePortController.text) ?? 4001,
    );

    cfd.storeName.value = _storeNameController.text.trim();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hardware peripheral and terminal settings saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hardware Peripherals'),
        actions: [
          FilledButton.icon(
            onPressed: _saveAll,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTerminalCard(context, colorScheme),
                const SizedBox(height: 20),
                _buildPrinterCard(context, colorScheme),
                const SizedBox(height: 20),
                _buildDrawerCard(context, colorScheme),
                const SizedBox(height: 20),
                _buildScaleCard(context, colorScheme),
                const SizedBox(height: 20),
                _buildCfdCard(context, colorScheme),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal_outlined, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'POS Register & Terminal Identity',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Unique register identifier attached to every sale order, cashier shift, and printed thermal ticket in multi-counter stores.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _terminalIdController,
                    decoration: const InputDecoration(
                      labelText: 'Terminal ID / Code',
                      hintText: 'REG-01',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _terminalNameController,
                    decoration: const InputDecoration(
                      labelText: 'Register Name / Counter',
                      hintText: 'Counter 1 (Main Till)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _branchCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      hintText: 'MAIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.print_outlined, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Thermal Receipt Printer (ESC/POS)',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<PrinterConnectionType>(
              initialValue: _selectedPrinterType,
              decoration: const InputDecoration(
                labelText: 'Connection Mode',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: PrinterConnectionType.network,
                  child: Text('Network / Wi-Fi (Direct TCP Port 9100)'),
                ),
                DropdownMenuItem(
                  value: PrinterConnectionType.system,
                  child: Text('System Spooler (USB / Windows / CUPS)'),
                ),
                DropdownMenuItem(
                  value: PrinterConnectionType.virtual,
                  child: Text('Virtual Simulator (Testing / Preview)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedPrinterType = val);
              },
            ),
            if (_selectedPrinterType == PrinterConnectionType.network) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: TextField(
                      controller: _printerIpController,
                      decoration: const InputDecoration(
                        labelText: 'Printer IP Address',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _printerPortController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '9100',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<EscPosPaperSize>(
                    initialValue: _selectedPaperSize,
                    decoration: const InputDecoration(
                      labelText: 'Paper Roll Size',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: EscPosPaperSize.mm80,
                        child: Text('80mm (Standard 3-inch, 48 cols)'),
                      ),
                      DropdownMenuItem(
                        value: EscPosPaperSize.mm58,
                        child: Text('58mm (Compact 2-inch, 32 cols)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedPaperSize = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Automatic Paper Cut'),
              subtitle: const Text('Sends GS V cut pulse at end of receipt'),
              value: _autoCut,
              onChanged: (val) => setState(() => _autoCut = val),
            ),
            SwitchListTile(
              title: const Text('Auto-Kick Drawer on Cash Sale'),
              subtitle: const Text('Pops drawer immediately after cash transaction'),
              value: _autoDrawer,
              onChanged: (val) => setState(() => _autoDrawer = val),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await printer.printProductLabel(
                      productName: 'Shimla Royal Apple',
                      price: 180.0,
                      weightKg: 1.000,
                      barcode: '890123456789',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Test barcode label generated successfully!'
                              : 'Label print failed'),
                          backgroundColor: ok ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Test Barcode Label'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await printer.saveSettings(
                      type: _selectedPrinterType,
                      ip: _printerIpController.text,
                      port: int.tryParse(_printerPortController.text) ?? 9100,
                      paper: _selectedPaperSize,
                      cut: _autoCut,
                      autoDrawer: _autoDrawer,
                      pin: _drawerPin,
                      reqPin: _reqPin,
                      mPin: _managerPinController.text,
                    );
                    final ok = await printer.testPrint();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok
                              ? 'Test ticket sent successfully!'
                              : 'Test print failed: check connection'),
                          backgroundColor: ok ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Print Test Receipt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.point_of_sale_outlined, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Cash Drawer Pulse Trigger',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _drawerPin,
                    decoration: const InputDecoration(
                      labelText: 'Printer Connector Pin',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('Pin 2 (Standard Epson/Star RJ12)')),
                      DropdownMenuItem(value: 5, child: Text('Pin 5 (Secondary Drawer RJ12)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _drawerPin = val);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _managerPinController,
                    decoration: const InputDecoration(
                      labelText: 'Manager Override PIN',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Require Manager PIN for Manual Open'),
              subtitle: const Text('Prevents unauthorized manual drawer opening'),
              value: _reqPin,
              onChanged: (val) => setState(() => _reqPin = val),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final ok = await printer.kickCashDrawer(
                    managerPinInput: _managerPinController.text,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? 'Cash drawer pulse sent!' : 'Cash drawer trigger failed'),
                        backgroundColor: ok ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.lock_open),
                label: const Text('Test Open Cash Drawer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScaleCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.scale_outlined, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Digital Weighing Scale',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ScaleMode>(
              initialValue: _selectedScaleMode,
              decoration: const InputDecoration(
                labelText: 'Scale Mode',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: ScaleMode.simulator,
                  child: Text('Virtual Weight Simulator (Interactive Demo)'),
                ),
                DropdownMenuItem(
                  value: ScaleMode.network,
                  child: Text('Network / Serial Scale (CAS / Essae / Toledo ASCII)'),
                ),
                DropdownMenuItem(
                  value: ScaleMode.manual,
                  child: Text('Disabled (Manual keypad entry only)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedScaleMode = val);
              },
            ),
            if (_selectedScaleMode == ScaleMode.network) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: TextField(
                      controller: _scaleIpController,
                      decoration: const InputDecoration(
                        labelText: 'Scale Serial-to-IP Bridge',
                        hintText: '192.168.1.150',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _scalePortController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '4001',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // Live Scale Gauge
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Live Scale Reading:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Obx(() => Row(
                              children: [
                                Text(
                                  '${scale.currentWeight.value.toStringAsFixed(3)} kg',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Chip(
                                  label: Text(
                                    scale.isStable.value ? 'STABLE' : 'UNSTABLE',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: scale.isStable.value ? Colors.green[800] : Colors.amber[900],
                                    ),
                                  ),
                                  backgroundColor: scale.isStable.value
                                      ? Colors.green.withValues(alpha: 0.15)
                                      : Colors.amber.withValues(alpha: 0.15),
                                ),
                              ],
                            )),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => scale.zero(),
                        child: const Text('ZERO'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => scale.tare(),
                        child: const Text('TARE'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_selectedScaleMode == ScaleMode.simulator) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _simWeightController,
                      decoration: const InputDecoration(
                        labelText: 'Set Simulator Weight (kg)',
                        hintText: '1.250',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final val = double.tryParse(_simWeightController.text) ?? 1.0;
                      scale.setSimulatedWeight(val);
                    },
                    child: const Text('Simulate Load'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCfdCard(BuildContext context, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tv_outlined, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Customer Facing Display (CFD)',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _storeNameController,
              decoration: const InputDecoration(
                labelText: 'Store Name Displayed to Customer',
                hintText: 'Fresh Fruit Mart',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  cfd.storeName.value = _storeNameController.text.trim();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => const CustomerFacingDisplayScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Launch Customer Display Screen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
