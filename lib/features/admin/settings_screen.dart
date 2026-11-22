import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/env.dart';
import '../../core/errors/app_error.dart';
import '../../core/permissions.dart';
import '../../core/strings.dart';
import '../../core/state/app_cache.dart';
import '../../core/supabase_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import '../inventory/data/inventory_providers.dart';
import '../sales/data/sales.dart';

/// Tenant settings stored as key/value rows in `app_settings`. The service-role
/// key is never needed here: RLS restricts writes to admins.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.initialRows,
    this.initialError,
  });

  /// Optional preloaded rows keep this screen pumpable in widget tests.
  final List<Map<String, dynamic>>? initialRows;
  final String? initialError;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

const List<String> _textKeys = [
  'pharmacy_name',
  'tagline',
  'address',
  'phone',
  'tin',
  'license_no',
  // Kept for display/editing, but the money formatter is hard-coded to ETB.
  'currency',
  'receipt_footer',
];

const List<String> _numberKeys = [
  'vat_rate',
  'low_stock_default',
  'expiry_alert_days',
  'max_cashier_discount_pct',
];

const _invalidNumber = 'Enter a valid number.';
const _negativeNumber = 'Cannot be negative.';
const _percentageRange = 'Enter a value between 0 and 100.';
const _wholeNumber = 'Enter a whole number.';

/// Pure validator shared by the settings form and its unit tests.
/// Empty optional fields are accepted; saved values are always non-negative.
String? validateSettingNumber(String key, String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  if (parsed == null) return _invalidNumber;
  if (parsed < 0) return _negativeNumber;
  final isPercentage = key == 'vat_rate' || key == 'max_cashier_discount_pct';
  if (isPercentage && parsed > 100) return _percentageRange;
  final isWhole = key == 'low_stock_default' || key == 'expiry_alert_days';
  if (isWhole && parsed != parsed.roundToDouble()) return _wholeNumber;
  return null;
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, Map<String, dynamic>> _rows = {};
  String _logoUrl = '';
  Uint8List? _logoBytes;
  bool _loading = true;
  bool _saving = false;
  bool _publishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final key in [..._textKeys, ..._numberKeys]) {
      _controllers[key] = TextEditingController();
    }
    if (widget.initialRows != null || widget.initialError != null) {
      _applyRows(widget.initialRows ?? const []);
      _error = widget.initialError;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applyRows(List<Map<String, dynamic>> rows) {
    _rows.clear();
    for (final map in rows) {
      final key = map['key'] as String?;
      if (key != null) _rows[key] = map;
    }
    for (final key in [..._textKeys, ..._numberKeys]) {
      _controllers[key]!.text = _read(_rows[key]);
    }
    // Stored as a fraction (0.15); the field works in percent (15).
    final vatPercent = num.tryParse(_controllers['vat_rate']!.text);
    if (vatPercent != null) {
      _controllers['vat_rate']!.text = _plainNumber(vatPercent * 100);
    }
    _logoUrl = _read(_rows['logo_url']);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      final rows = await SupabaseService.client.from('app_settings').select();
      if (!mounted) return;
      _applyRows(List<Map<String, dynamic>>.from(
          (rows as List).map((row) => Map<String, dynamic>.from(row as Map))));
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMapper.from(e).message;
        _loading = false;
      });
    }
  }

  String _plainNumber(num value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  String _read(Map<String, dynamic>? row) {
    if (row == null) return '';
    final value = row['value'];
    if (value == null) return '';
    if (value is Map) return (value['value'] ?? value['_'] ?? '').toString();
    return value.toString();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final client = SupabaseService.client;
      // Currency is display-only: the money formatter is hard-coded to ETB,
      // so never write it back to app_settings.
      final values = <String, dynamic>{
        for (final key in _textKeys.where((key) => key != 'currency'))
          key: _controllers[key]!.text.trim(),
        for (final key in _numberKeys)
          key: num.tryParse(_controllers[key]!.text.trim()) ?? 0,
      };
      // The field is in percent; app_settings stores the fraction (15 -> 0.15).
      if (values['vat_rate'] is num) {
        values['vat_rate'] = (values['vat_rate'] as num) / 100;
      }
      if (_logoBytes != null) {
        values['logo_url'] = await _uploadLogo();
      } else if (_logoUrl.isNotEmpty) {
        values['logo_url'] = _logoUrl;
      }
      values.putIfAbsent('vat_rate', () => Env.defaultVatRate);

      final failed = <String>[];
      var saved = 0;
      for (final entry in values.entries) {
        try {
          await client.from('app_settings').upsert({
            'key': entry.key,
            'value': entry.value,
          });
          saved++;
        } catch (_) {
          // Keep going: a single rejected key must not roll back every other
          // setting or hide the rest of the save result from the user.
          failed.add(entry.key);
        }
      }
      if (!mounted) return;
      if (failed.isNotEmpty) {
        final message = saved == 0
            ? '${S.somethingWrong} No settings were saved.'
            : 'Some settings were saved, but these could not be updated: '
                '${failed.join(', ')}. Please try again.';
        AppSnackbar.error(context, message);
        await _load();
        return;
      }
      // Settings are cached in these providers; drop both the provider state
      // and the underlying TTL cache so receipts/alerts pick up the changes.
      ref.invalidate(receiptSettingsProvider);
      ref.invalidate(expiryAlertDaysProvider);
      ref.invalidateCache(CacheTag.settings);
      AppSnackbar.success(context, S.saved);
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      await SupabaseService.client.rpc('publish_app_settings');
      if (!mounted) return;
      ref.invalidateCache(CacheTag.settings);
      if (!mounted) return;
      AppSnackbar.success(context, S.settingsPublished);
      // The published rows are the ones displayed here; refresh them.
      await _load();
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<String> _uploadLogo() async {
    const bucket = 'branding';
    final path = 'logo-${DateTime.now().millisecondsSinceEpoch}.png';
    await SupabaseService.client.storage.from(bucket).uploadBinary(
        path, _logoBytes!,
        fileOptions: const FileOptions(upsert: true, contentType: 'image/png'));
    return SupabaseService.client.storage.from(bucket).getPublicUrl(path);
  }

  Future<void> _pickLogo() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1024,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _logoBytes = bytes);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.settings, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: S.settings,
                subtitle:
                    canEdit ? null : '${S.view} ${S.settings.toLowerCase()}',
                actions: [
                  if (canEdit)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PrimaryButton(
                        label: S.save,
                        loading: _saving,
                        onPressed: _save,
                        width: 130,
                      ),
                    ),
                  if (canEdit)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PrimaryButton(
                        label: S.publishSettings,
                        loading: _publishing,
                        onPressed: _publish,
                        width: 180,
                      ),
                    ),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                ErrorState(message: _error!, onRetry: _load)
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Appearance',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Choose light, dark, or system theme. Your choice is saved on this device.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 16),
                                    const ThemeModeToggle(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (role == AppRole.superAdmin) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Security & Passwords',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Change your own password or reset passwords for staff accounts you manage.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: [
                                          SecondaryButton(
                                            label: 'Change my password',
                                            icon: Icons.lock_reset_outlined,
                                            width: 220,
                                            onPressed: () =>
                                                context.go('/profile'),
                                          ),
                                          SecondaryButton(
                                            label: 'Manage staff passwords',
                                            icon:
                                                Icons.manage_accounts_outlined,
                                            width: 220,
                                            onPressed: () =>
                                                context.go('/admin/users'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(S.pharmacyName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 38,
                                          backgroundColor:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? AppColors.darkElevated
                                                  : AppColors.pink50,
                                          backgroundImage: _logoBytes != null
                                              ? MemoryImage(_logoBytes!)
                                              : (_logoUrl.isNotEmpty
                                                  ? NetworkImage(_logoUrl)
                                                  : null) as ImageProvider?,
                                          child: _logoBytes == null &&
                                                  _logoUrl.isEmpty
                                              ? const Icon(Icons.local_pharmacy,
                                                  size: 34,
                                                  color: AppColors.pink600)
                                              : null,
                                        ),
                                        const SizedBox(width: 16),
                                        if (canEdit)
                                          SecondaryButton(
                                            label: S.uploadLogo,
                                            width: 160,
                                            onPressed: _pickLogo,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    _field(S.pharmacyName, 'pharmacy_name',
                                        canEdit),
                                    const SizedBox(height: 14),
                                    _field(S.taglineLabel, 'tagline', canEdit),
                                    const SizedBox(height: 14),
                                    _field(S.address, 'address', canEdit),
                                    const SizedBox(height: 14),
                                    _field(S.phone, 'phone', canEdit,
                                        keyboard: TextInputType.phone),
                                    const SizedBox(height: 14),
                                    _field(S.tin, 'tin', canEdit,
                                        keyboard: TextInputType.number),
                                    const SizedBox(height: 14),
                                    _field(S.licenseNo, 'license_no', canEdit),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(S.reports,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 14,
                                      children: [
                                        SizedBox(
                                            width: 200,
                                            child: _field(
                                                S.currency, 'currency', false,
                                                hint:
                                                    'Display only; amounts use ETB')),
                                        SizedBox(
                                            width: 200,
                                            child: _field(
                                                S.vatRate, 'vat_rate', canEdit,
                                                keyboard: const TextInputType
                                                    .numberWithOptions(
                                                    decimal: true),
                                                number: true)),
                                        SizedBox(
                                            width: 200,
                                            child: _field(S.lowStockDefault,
                                                'low_stock_default', canEdit,
                                                keyboard: TextInputType.number,
                                                number: true)),
                                        SizedBox(
                                            width: 200,
                                            child: _field(S.expiryAlertDays,
                                                'expiry_alert_days', canEdit,
                                                keyboard: TextInputType.number,
                                                number: true)),
                                        SizedBox(
                                            width: 200,
                                            child: _field(
                                                S.maxDiscount,
                                                'max_cashier_discount_pct',
                                                canEdit,
                                                keyboard: const TextInputType
                                                    .numberWithOptions(
                                                    decimal: true),
                                                number: true)),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    _field(S.receiptFooter, 'receipt_footer',
                                        canEdit,
                                        maxLines: 3),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    String key,
    bool enabled, {
    TextInputType? keyboard,
    bool number = false,
    int maxLines = 1,
    String? hint,
  }) {
    return AppTextField(
      label: label,
      controller: _controllers[key]!,
      enabled: enabled,
      keyboardType: keyboard,
      maxLines: maxLines,
      hint: hint,
      validator: !number ? null : (value) => validateSettingNumber(key, value),
    );
  }
}
