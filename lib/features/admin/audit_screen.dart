import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/errors/app_error.dart';
import '../../core/strings.dart';
import '../../core/supabase_client.dart';
import '../../core/widgets.dart';

/// Read-only audit trail over the `audit_logs` table.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _tableFilter;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!SupabaseService.isReady) throw const SupabaseNotConfigured();
      final client = SupabaseService.client;
      var query = client.from('audit_logs').select();
      if (_tableFilter != null) {
        query = query.eq('table_name', _tableFilter!);
      }
      if (_from != null) {
        query = query.gte('created_at', _from!.toUtc().toIso8601String());
      }
      if (_to != null) {
        query = query.lte(
            'created_at',
            DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59)
                .toUtc()
                .toIso8601String());
      }
      final rows = await query.order('created_at', ascending: false).limit(500);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppErrorMapper.from(e).message;
        _loading = false;
      });
    }
  }

  List<String> get _tables {
    final values = <String>{
      for (final row in _rows)
        if (row['table_name'] != null) row['table_name'] as String,
    }.toList();
    values.sort();
    return values;
  }

  List<Map<String, dynamic>> get _filtered => _rows.where((row) {
        if (_tableFilter != null && row['table_name'] != _tableFilter) return false;
        return true;
      }).toList();

  String _short(String? value, [int max = 70]) {
    if (value == null || value.isEmpty) return '—';
    return value.length <= max ? value : '${value.substring(0, max)}…';
  }

  String _format(dynamic value, {bool pretty = false}) {
    if (value == null) return '—';
    if (value is Map || value is List) {
      return pretty
          ? const JsonEncoder.withIndent('  ').convert(value)
          : jsonEncode(value);
    }
    return value.toString();
  }

  void _showDetail(Map<String, dynamic> row) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${row['action'] ?? S.actionLabel} — ${row['table_name'] ?? ''}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailLine('${S.dateFrom}/${S.dateTo}',
                    row['created_at'] == null ? '—' : formatDateTime(DateTime.parse(row['created_at'] as String))),
                _detailLine(S.actionLabel, _format(row['action'])),
                _detailLine(S.tableName, _format(row['table_name'])),
                _detailLine('Record', _format(row['record_id'])),
                _detailLine('User', _format(row['user_id'])),
                _detailLine('Branch', _format(row['branch_id'])),
                _detailLine(S.oldValue, _format(row['old_data'], pretty: true)),
                _detailLine(S.newValue, _format(row['new_data'], pretty: true)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.close)),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: [
              TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: value),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: S.audit,
              actions: [
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorState(message: _error!, onRetry: _load)
            else
              Expanded(
                child: Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 200,
                          child: AppDropdown<String?>(
                            label: S.tableName,
                            value: _tableFilter,
                            items: [
                              const DropdownMenuItem(value: null, child: Text(S.all)),
                              for (final table in _tables)
                                DropdownMenuItem(value: table, child: Text(table)),
                            ],
                            onChanged: (value) {
                              setState(() => _tableFilter = value);
                              _load();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: DatePickerField(
                            label: S.dateFrom,
                            value: _from,
                            onChanged: (value) {
                              setState(() => _from = value);
                              _load();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: DatePickerField(
                            label: S.dateTo,
                            value: _to,
                            onChanged: (value) {
                              setState(() => _to = value);
                              _load();
                            },
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _tableFilter = null;
                              _from = null;
                              _to = null;
                            });
                            _load();
                          },
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text(S.reset),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: DataTablePlus(
                        columns: const [
                          'When',
                          'Actor',
                          S.actionLabel,
                          S.tableName,
                          S.oldValue,
                          S.newValue,
                          S.view,
                        ],
                        exportFileName: 'yusra-audit-log.csv',
                        rows: [
                          for (final row in _filtered)
                            DataTablePlusRow(
                              cells: [
                                row['created_at'] == null
                                    ? '—'
                                    : formatDateTime(DateTime.parse(row['created_at'] as String)),
                                _short(row['user_id']?.toString()),
                                _short(row['action'] as String?),
                                _short(row['table_name'] as String?),
                                _short(_format(row['old_data'])),
                                _short(_format(row['new_data'])),
                                '',
                              ],
                              actions: [
                                IconButton(
                                  tooltip: S.view,
                                  icon: const Icon(Icons.visibility_outlined, size: 18),
                                  onPressed: () => _showDetail(row),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
