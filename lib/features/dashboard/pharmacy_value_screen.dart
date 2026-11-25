import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets.dart';
import '../inventory/data/inventory_models.dart';
import '../inventory/data/inventory_providers.dart';

class PharmacyValueScreen extends ConsumerWidget {
  const PharmacyValueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(stockSummaryProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pharmacy value')),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(stockSummaryProvider),
        ),
        data: (stock) {
          final categories = categoriesAsync.valueOrNull ?? const [];
          final catNames = <String, String>{
            for (final c in categories) c.id: c.name,
          };
          final byCategory = <String, List<StockSummary>>{};
          double totalCost = 0;
          double totalRetail = 0;
          for (final item in stock) {
            final qty = item.availableQty.toDouble();
            final cost = qty * item.costPrice;
            final retail = qty * item.sellingPrice;
            totalCost += cost;
            totalRetail += retail;
            final catName =
                (item.categoryId != null ? catNames[item.categoryId] : null) ??
                    'Uncategorized';
            byCategory.putIfAbsent(catName, () => []).add(item);
          }
          final categoryNames = byCategory.keys.toList()..sort();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(stockSummaryProvider);
              ref.invalidate(categoriesProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryChip(
                        label: 'Retail value', value: formatMoney(totalRetail)),
                    _SummaryChip(
                        label: 'Cost value', value: formatMoney(totalCost)),
                    _SummaryChip(label: 'Products', value: '${stock.length}'),
                  ],
                ),
                const SizedBox(height: 16),
                for (final cat in categoryNames) ...[
                  _CategorySection(
                    name: cat,
                    items: byCategory[cat]!,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.plum800.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold500.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({required this.name, required this.items});
  final String name;
  final List<StockSummary> items;

  @override
  Widget build(BuildContext context) {
    double cost = 0;
    double retail = 0;
    for (final item in items) {
      final qty = item.availableQty.toDouble();
      cost += qty * item.costPrice;
      retail += qty * item.sellingPrice;
    }
    return Card(
      child: ExpansionTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${items.length} items · Cost ${formatMoney(cost)} · Retail ${formatMoney(retail)}'),
        children: [
          for (final item in items)
            ListTile(
              dense: true,
              title: Text(item.name),
              subtitle: Text(
                  'Qty ${item.availableQty} · Cost ${formatMoney(item.costPrice)} · Sell ${formatMoney(item.sellingPrice)}'),
              trailing: Text(
                formatMoney(item.availableQty * item.costPrice),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
