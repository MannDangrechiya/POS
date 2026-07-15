import 'package:flutter/material.dart';
import '../../core/observability/error_ui.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/firestore/firestore_parse.dart';
import '../../core/firestore/firestore_rule_safe_update.dart';
import '../../data/models/setting_model.dart';
import '../../data/models/user_model.dart';
import '../../core/rbac/role_constants.dart';
import '../../core/firestore/firestore_stream_cache.dart';
import '../../routing/permission_gate.dart';
import '../../routing/screen_permission.dart';

/// Well-known shop-level setting keys with dedicated UI (Requirement in
/// Detail §32.2: "Change tax rules", "Enable/disable payment methods",
/// "Configure POS behavior"). Any other key still goes through the generic
/// list below.
class _KnownSettingKeys {
  static const taxRatePercent = 'tax_rate_percent';
  static const paymentCashEnabled = 'payment_cash_enabled';
  static const paymentUpiEnabled = 'payment_upi_enabled';
  static const paymentCardEnabled = 'payment_card_enabled';
  static const posAutoPrintReceipt = 'pos_auto_print_receipt';

  static const all = {
    taxRatePercent,
    paymentCashEnabled,
    paymentUpiEnabled,
    paymentCardEnabled,
    posAutoPrintReceipt,
  };
}

/// Settings screen: Shop-level (Admin) or System-level (Super Admin).
/// Read/write per Firestore rules; future-only application per requirements.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _shopId;
  bool _isSuperAdmin = false;
  bool _loading = true;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _settingsStream;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final u = UserModel.tryFromDocument(doc);
        if (u == null) {
          setState(() => _loading = false);
          return;
        }
        setState(() {
          _shopId = u.shopId;
          _isSuperAdmin = u.role == RoleConstants.superAdmin;
          _loading = false;
          _initSettingsStream();
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'AdminSettingsScreen._load');
      setState(() => _loading = false);
    }
  }

  void _initSettingsStream() {
    final query = _buildQuery();
    final key = _isSuperAdmin
        ? 'admin_settings_system'
        : 'admin_settings_shop_${_shopId ?? ''}';
    _settingsStream ??=
        FirestoreStreamCache.instance.querySnapshots(query, key: key);
  }

  Query<Map<String, dynamic>> _buildQuery() {
    if (_isSuperAdmin) {
      return FirebaseFirestore.instance
          .collection('settings')
          .where('scope', isEqualTo: 'system')
          .orderBy('key');
    }
    final shopId = _shopId ?? '';
    return FirebaseFirestore.instance
        .collection('settings')
        .where('scope', isEqualTo: 'shop')
        .where('shopId', isEqualTo: shopId)
        .orderBy('key');
  }

  /// Writes an audit_logs entry for a settings change via the extended
  /// logAuthEvent callable (see auth_audit.ts — it now accepts entityType/
  /// entityId/metadata instead of hardcoding a generic 'AUTH' entry).
  /// Requirement in Detail §32.3 / §37.2: settings changes must be logged.
  /// Best-effort: a logging failure must not block the settings write that
  /// already succeeded.
  Future<void> _auditSettingChange({
    required String action,
    required String settingId,
    required String key,
    required dynamic oldValue,
    required dynamic newValue,
  }) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('logAuthEvent').call({
        'action': action,
        'shopId': _isSuperAdmin ? 'system' : (_shopId ?? ''),
        'entityType': 'setting',
        'entityId': settingId,
        'metadata': {
          'key': key,
          'oldValue': oldValue,
          'newValue': newValue,
        },
      });
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'SettingsScreen.audit');
    }
  }

  String _settingIdFor(String key) =>
      _isSuperAdmin ? 'system_$key' : 'shop_${_shopId}_$key';

  /// Shared write path for the domain-specific controls below — same
  /// settings collection/shape as the generic editor, just with a typed
  /// value and a fixed, well-known key.
  Future<void> _setKnownSetting(
    BuildContext context,
    String key,
    dynamic newValue, {
    dynamic oldValue,
    bool requireConfirmation = false,
    String? confirmMessage,
  }) async {
    if (requireConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm change'),
          content: Text(
            confirmMessage ??
                'This changes a setting that affects live POS operations. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!context.mounted) return;

    final settingId = _settingIdFor(key);
    final now = Timestamp.now();
    final doc = <String, dynamic>{
      'settingId': settingId,
      'scope': _isSuperAdmin ? 'system' : 'shop',
      'key': key,
      'value': newValue,
      'updatedAt': now,
    };
    if (!_isSuperAdmin && _shopId != null) {
      doc['shopId'] = _shopId;
    }

    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc(settingId)
          .set(doc, SetOptions(merge: true));
      await _auditSettingChange(
        action: 'SETTING_UPDATED',
        settingId: settingId,
        key: key,
        oldValue: oldValue,
        newValue: newValue,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated ${key.replaceAll('_', ' ')}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGate(
      permission: ScreenPermission.adminSettings,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSuperAdmin ? 'System Settings' : 'Shop Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditSetting(context, null),
            tooltip: 'Add setting',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _settingsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          final allSettings = docs
              .map((d) {
                final map = FirestoreParse.queryDocumentData(d);
                if (map == null) return null;
                return SettingModel.tryFromMap({...map, 'settingId': d.id});
              })
              .whereType<SettingModel>()
              .toList();
          final knownByKey = {for (final s in allSettings) s.key: s.value};
          // Domain-specific controls (tax/payment/POS behavior) get their
          // own dedicated UI; the generic key/value list below is for
          // anything else.
          final settings = allSettings
              .where((s) => !_KnownSettingKeys.all.contains(s.key))
              .toList();

          final domainSection = _isSuperAdmin
              ? const SizedBox.shrink()
              : _buildDomainSettingsCard(context, knownByKey);

          if (settings.isEmpty) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  domainSection,
                  if (!_isSuperAdmin) const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          'No custom settings yet',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _addOrEditSetting(context, null),
                          icon: const Icon(Icons.add),
                          label: const Text('Add setting'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: settings.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) return domainSection;
              final s = settings[index - 1];
              return Card(
                child: ListTile(
                  title: Text(s.key),
                  subtitle: Text(_valueDisplay(s.value)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _addOrEditSetting(context, s),
                      ),
                      if (_isSuperAdmin)
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteSetting(context, s),
                        ),
                    ],
                  ),
                  onTap: () => _addOrEditSetting(context, s),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _valueDisplay(dynamic value) {
    if (value == null) return '—';
    if (value is num) return value.toString();
    if (value is bool) return value ? 'Yes' : 'No';
    return value.toString();
  }

  /// Guards against disabling every payment method at once — that would
  /// leave Employees with no selectable option on the Payment Selection
  /// Screen, which is mandatory per Requirement in Detail §20.4.
  Future<void> _setPaymentMethodEnabled(
    BuildContext context, {
    required String key,
    required String label,
    required bool newValue,
    required bool oldValue,
    required bool otherMethodsEnabled,
  }) async {
    if (!newValue && !otherMethodsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'At least one payment method must stay enabled — enable '
            'another method before disabling $label.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await _setKnownSetting(
      context,
      key,
      newValue,
      oldValue: oldValue,
      requireConfirmation: !newValue,
      confirmMessage: 'Disable $label as a payment method for future orders?',
    );
  }

  /// Dedicated UI for the well-known shop-level settings (tax rate, payment
  /// method toggles, POS behavior) instead of forcing Admin to know exact
  /// key strings and free-type values — Requirement in Detail §32.2.
  Widget _buildDomainSettingsCard(
    BuildContext context,
    Map<String, dynamic> knownByKey,
  ) {
    final taxRate =
        (knownByKey[_KnownSettingKeys.taxRatePercent] as num?)?.toDouble() ?? 0;
    final cashEnabled =
        knownByKey[_KnownSettingKeys.paymentCashEnabled] as bool? ?? true;
    final upiEnabled =
        knownByKey[_KnownSettingKeys.paymentUpiEnabled] as bool? ?? true;
    final cardEnabled =
        knownByKey[_KnownSettingKeys.paymentCardEnabled] as bool? ?? true;
    final autoPrint =
        knownByKey[_KnownSettingKeys.posAutoPrintReceipt] as bool? ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Common Settings',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Applies only to future orders (§32.3).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tax rate (%)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    key: ValueKey('tax_rate_$taxRate'),
                    initialValue: taxRate.toStringAsFixed(2),
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onFieldSubmitted: (text) {
                      final parsed = double.tryParse(text.trim());
                      if (parsed == null || parsed < 0 || parsed > 100) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a tax rate between 0 and 100'),
                          ),
                        );
                        return;
                      }
                      _setKnownSetting(
                        context,
                        _KnownSettingKeys.taxRatePercent,
                        parsed,
                        oldValue: taxRate,
                        requireConfirmation: true,
                        confirmMessage:
                            'Change tax rate from ${taxRate.toStringAsFixed(2)}% '
                            'to ${parsed.toStringAsFixed(2)}%? This applies to '
                            'future orders only.',
                      );
                    },
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            Text(
              'Payment methods',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cash'),
              value: cashEnabled,
              onChanged: (v) => _setPaymentMethodEnabled(
                context,
                key: _KnownSettingKeys.paymentCashEnabled,
                label: 'Cash',
                newValue: v,
                oldValue: cashEnabled,
                otherMethodsEnabled: upiEnabled || cardEnabled,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('UPI / Online Payment'),
              value: upiEnabled,
              onChanged: (v) => _setPaymentMethodEnabled(
                context,
                key: _KnownSettingKeys.paymentUpiEnabled,
                label: 'UPI',
                newValue: v,
                oldValue: upiEnabled,
                otherMethodsEnabled: cashEnabled || cardEnabled,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Card'),
              value: cardEnabled,
              onChanged: (v) => _setPaymentMethodEnabled(
                context,
                key: _KnownSettingKeys.paymentCardEnabled,
                label: 'Card',
                newValue: v,
                oldValue: cardEnabled,
                otherMethodsEnabled: cashEnabled || upiEnabled,
              ),
            ),
            const Divider(height: 32),
            Text(
              'POS behavior',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-print receipt on order confirmation'),
              value: autoPrint,
              onChanged: (v) => _setKnownSetting(
                context,
                _KnownSettingKeys.posAutoPrintReceipt,
                v,
                oldValue: autoPrint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addOrEditSetting(BuildContext context, SettingModel? existing) async {
    final keyController = TextEditingController(text: existing?.key ?? '');
    final valueController = TextEditingController(
      text: existing?.value?.toString() ?? '',
    );
    final isNew = existing == null;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? 'Add setting' : 'Edit setting'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  hintText: 'e.g. low_stock_threshold',
                ),
                enabled: isNew,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: valueController,
                decoration: const InputDecoration(
                  labelText: 'Value',
                  hintText: 'e.g. 10',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final key = keyController.text.trim();
              final valueStr = valueController.text.trim();
              if (key.isEmpty) return;
              num? valueNum = num.tryParse(valueStr);
              Navigator.pop(context, {
                'key': key,
                'value': valueNum ?? valueStr,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || !context.mounted) return;

    final key = result['key'] as String;
    final value = result['value'];

    try {
      final db = FirebaseFirestore.instance;
      final now = DateTime.now();
      final timestamp = Timestamp.fromDate(now);

      if (isNew) {
        final settingId = _isSuperAdmin
            ? 'system_$key'
            : 'shop_${_shopId}_$key';
        final doc = <String, dynamic>{
          'settingId': settingId,
          'scope': _isSuperAdmin ? 'system' : 'shop',
          'key': key,
          'value': value,
          'updatedAt': timestamp,
        };
        if (!_isSuperAdmin && _shopId != null) {
          doc['shopId'] = _shopId;
        }
        await db.collection('settings').doc(settingId).set(doc);
        await _auditSettingChange(
          action: 'SETTING_CREATED',
          settingId: settingId,
          key: key,
          oldValue: null,
          newValue: value,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Setting added')),
          );
        }
      } else {
        await db.collection('settings').doc(existing.settingId).update(
              FirestoreRuleSafeUpdate.setting(
                existing,
                changes: {
                  'value': value,
                  'updatedAt': timestamp,
                },
              ),
            );
        await _auditSettingChange(
          action: 'SETTING_UPDATED',
          settingId: existing.settingId,
          key: key,
          oldValue: existing.value,
          newValue: value,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Setting updated')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSetting(BuildContext context, SettingModel s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete setting?'),
        content: Text('Delete "${s.key}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc(s.settingId)
          .delete();
      await _auditSettingChange(
        action: 'SETTING_DELETED',
        settingId: s.settingId,
        key: s.key,
        oldValue: s.value,
        newValue: null,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Setting deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
