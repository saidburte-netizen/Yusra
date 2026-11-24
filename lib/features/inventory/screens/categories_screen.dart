import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/permissions.dart';
import '../../../core/state/invalidation.dart';
import '../../../core/supabase_client.dart';
import '../../../core/widgets.dart';
import '../data/inventory_models.dart';
import '../data/inventory_providers.dart';
import '../widgets/stock_widgets.dart';
import '../../../core/errors/app_error.dart';
import '../widgets/responsive_ui.dart';

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
                  ResponsivePrimaryButton(
                    label: 'New category',
                    icon: Icons.add,
                    onPressed: () => _edit(context, ref, null),
                  ),
              ],
            ),
            stockState(
              state,
              onRetry: () => ref.invalidate(categoriesProvider),
              builder: (items) => Expanded(
                child: ResponsiveDataTablePlus(
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
                          RowActions(actions: [
                            RowAction(
                              label: 'Edit',
                              icon: Icons.edit_outlined,
                              allowed: canEdit,
                              onSelected: () => _edit(context, ref, item),
                              mutation: Mutation.saveCategory,
                            ),
                            RowAction(
                              label: item.isActive ? 'Deactivate' : 'Reactivate',
                              icon: item.isActive
                                  ? Icons.block_outlined
                                  : Icons.check_circle_outline,
                              allowed: canEdit,
                              confirmTitle: item.isActive
                                  ? 'Deactivate category'
                                  : 'Reactivate category',
                              confirmMessage:
                                  '${item.name} will ${item.isActive ? 'no longer' : 'again'} be available.',
                              onSelected: () => _toggle(context, ref, item),
                              mutation: Mutation.saveCategory,
                            ),
                            RowAction(
                              label: 'Delete',
                              icon: Icons.delete_outline,
                              allowed: canEdit,
                              danger: true,
                              confirmTitle: 'Delete category',
                              confirmMessage:
                                  'Delete ${item.name}? Categories in use cannot be deleted.',
                              onSelected: () => _delete(context, ref, item),
                              mutation: Mutation.saveCategory,
                            ),
                          ]),
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

  Future<String?> _edit(
      BuildContext context, WidgetRef ref, Category? item) async {
    final name = TextEditingController(text: item?.name ?? '');
    final description = TextEditingController(text: item?.description ?? '');
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item == null ? 'New category' : 'Edit category'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'Name',
                  controller: name,
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Required' : null,
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
          ResponsivePrimaryButton(
            label: 'Save',
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
    if (saved != true) return null;
    try {
      await ref.read(inventoryRepositoryProvider).saveCategory(
        {
          'name': name.text.trim(),
          'description':
              description.text.trim().isEmpty ? null : description.text.trim(),
        },
        id: item?.id,
      );
      ref.invalidate(categoriesProvider);
      return 'Category saved.';
    } catch (e) {
      throw AppErrorMapper.from(e);
    }
  }

  Future<String?> _toggle(
      BuildContext context, WidgetRef ref, Category item) async {
    await ref
        .read(inventoryRepositoryProvider)
        .setCategoryActive(item.id, !item.isActive);
    ref.invalidate(categoriesProvider);
    return item.isActive ? 'Category deactivated.' : 'Category reactivated.';
  }

  /// A category with medicines is in use: block the delete with a clear reason.
  Future<String?> _delete(
      BuildContext context, WidgetRef ref, Category item) async {
    final rows = await SupabaseService.client
        .from('medicines')
        .select('id')
        .eq('category_id', item.id)
        .limit(1);
    if ((rows as List).isNotEmpty) {
      throw AppError(
          'This category is in use by medicines. Deactivate it instead.');
    }
    await SupabaseService.client.from('categories').delete().eq('id', item.id);
    ref.invalidate(categoriesProvider);
    return 'Category deleted.';
  }
}
