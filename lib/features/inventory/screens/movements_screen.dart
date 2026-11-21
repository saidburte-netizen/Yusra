import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/widgets.dart';
import '../data/inventory_providers.dart';
import '../widgets/stock_widgets.dart';

class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({super.key});

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  String? _type;
  DateTime? _from;
  DateTime? _to;
  final _medicine = TextEditingController();
  final _user = TextEditingController();

  static const types = [
    'opening',
    'purchase',
    'sale',
    'sale_return',
    'void_restore',
    'adjustment',
    'expired_writeoff',
    'damage',
  ];

  @override
  void dispose() {
    _medicine.dispose();
    _user.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(movementsProvider(
      (medicineId: null, type: _type),
    ));
    final medicines = ref.watch(medicinesProvider(
      (query: _medicine.text, categoryId: null),
    ));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageHeader(
              title: 'Movements ledger',
              subtitle: 'Every stock change, newest first',
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 240,
                  child: AppTextField(
                    label: 'Medicine',
                    controller: _medicine,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: AppDropdown<String?>(
                    label: 'Movement type',
                    value: _type,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      for (final type in types)
                        DropdownMenuItem(value: type, child: Text(type)),
                    ],
                    onChanged: (value) => setState(() => _type = value),
                  ),
                ),
                DatePickerField(
                  label: 'From',
                  value: _from,
                  onChanged: (value) => setState(() => _from = value),
                ),
                DatePickerField(
                  label: 'To',
                  value: _to,
                  onChanged: (value) => setState(() => _to = value),
                ),
                SizedBox(
                  width: 180,
                  child: AppTextField(
                    label: 'User ID',
                    controller: _user,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            stockState(
              state,
              onRetry: () => ref.invalidate(movementsProvider(
                (medicineId: null, type: _type),
              )),
              builder: (items) {
                final medicineIds = medicines.value
                        ?.where((item) => item.name
                            .toLowerCase()
                            .contains(_medicine.text.toLowerCase()))
                        .map((item) => item.id)
                        .toSet() ??
                    <String>{};
                final visible = items.where((movement) {
                  if (_medicine.text.isNotEmpty &&
                      !medicineIds.contains(movement.medicineId)) {
                    return false;
                  }
                  if (_user.text.isNotEmpty &&
                      !(movement.createdBy ?? '')
                          .toLowerCase()
                          .contains(_user.text.toLowerCase())) {
                    return false;
                  }
                  if (_from != null && movement.createdAt != null) {
                    if (movement.createdAt!.isBefore(_from!)) return false;
                  }
                  if (_to != null && movement.createdAt != null) {
                    if (movement.createdAt!
                        .isAfter(_to!.add(const Duration(days: 1)))) {
                      return false;
                    }
                  }
                  return true;
                }).toList();
                return Expanded(
                  child: DataTablePlus(
                    columns: const [
                      'Date',
                      'Medicine',
                      'Type',
                      'Change',
                      'Reference',
                      'Reason',
                    ],
                    rows: [
                      for (final movement in visible)
                        DataTablePlusRow(
                          cells: [
                            movement.createdAt == null
                                ? '—'
                                : formatDateTime(movement.createdAt!),
                            movement.medicineName ?? '—',
                            movement.type,
                            '${movement.quantityChange > 0 ? '+' : ''}${movement.quantityChange}',
                            movement.referenceType ?? '—',
                            movement.reason ?? '—',
                          ],
                        ),
                    ],
                    exportFileName: 'yusra-movements.csv',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
