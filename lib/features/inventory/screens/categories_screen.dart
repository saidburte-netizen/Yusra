import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions.dart';
import '../../../core/widgets.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../widgets/stock_widgets.dart';
import '../../../core/errors/app_error.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(categoriesProvider);
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.medicines, PermAction.edit);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Categories',
              subtitle: 'Group medicines for faster browsing',
              actions: [
                if (canEdit)
                  PrimaryButton(
                    label: 'New category',
                    icon: Icons.add,
                    width: 160,
                    onPressed: () => _edit(context, ref, null),
                  ),
              ],
            ),
            stockState(
              state,
              onRetry: () => ref.invalidate(categoriesProvider),
              builder: (items) => Expanded(
                child: DataTablePlus(
                  columns: const ['Name', 'Description', 'Status', ''],
                  rows: [
                    for (final item in items)
                      DataTablePlusRow(
                        cells: [
                          item.name,
                          item.description ?? '—',
                          item.isActive ? 'Active' : 'Inactive',
                          '',
                        ],
                        actions: [
                          if (canEdit)
                            IconButton(
                              tooltip: 'Edit',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _edit(context, ref, item),
                            ),
                          if (canEdit)
                            IconButton(
                              tooltip: item.isActive ? 'Deactivate' : 'Reactivate',
                              icon: Icon(
                                item.isActive
                                    ? Icons.block_outlined
                                    : Icons.check_circle_outline,
                                size: 18,
                              ),
                              onPressed: () => _toggle(context, ref, item),
                            ),
                        ],
                      ),
                  ],
                  exportFileName: 'yusra-categories.csv',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Category? item) async {
    final name = TextEditingController(text: item?.name ?? '');
    final description = TextEditingController(text: item?.description ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item == null ? 'New category' : 'Edit category'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'Name',
                  controller: name,
                  validator: (value) => (value ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                AppTextField(label: 'Description', controller: description),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          PrimaryButton(
            label: 'Save',
            width: 110,
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await ref.read(inventoryRepositoryProvider).saveCategory(
            {
              'name': name.text.trim(),
              'description': description.text.trim().isEmpty
                  ? null
                  : description.text.trim(),
            },
            id: item?.id,
          );
      if (!context.mounted) return;
      AppSnackbar.success(context, 'Category saved.');
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, Category item) async {
    final confirm = await showConfirmDialog(
      context,
      title: item.isActive ? 'Deactivate category' : 'Reactivate category',
      message: '${item.name} will ${item.isActive ? 'no longer' : 'again'} be available.',
    );
    if (confirm != true) return;
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .setCategoryActive(item.id, !item.isActive);
      if (!context.mounted) return;
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (context.mounted) AppSnackbar.error(context, AppErrorMapper.from(e).message);
    }
  }
}
