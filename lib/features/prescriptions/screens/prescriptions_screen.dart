import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../../../core/strings.dart';
import '../../inventory/data/inventory_providers.dart';
import '../data/prescriptions.dart';
import '../../../core/errors/app_error.dart';

class PrescriptionsScreen extends ConsumerStatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  ConsumerState<PrescriptionsScreen> createState() => _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends ConsumerState<PrescriptionsScreen> {
  String? _status = 'pending';

  Future<void> _add() async {
    final branchId = ref.read(branchScopeProvider);
    if (branchId == null) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }
    final patient = TextEditingController();
    final age = TextEditingController();
    final prescriber = TextEditingController();
    final license = TextEditingController();
    final facility = TextEditingController();
    final notes = TextEditingController();
    final date = ValueNotifier<DateTime>(nowAddisAbaba());
    File? image;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Register prescription'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(
                  label: 'Patient name',
                  controller: patient,
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Age',
                        controller: age,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ValueListenableBuilder<DateTime>(
                        valueListenable: date,
                        builder: (context, value, _) => OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: value,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 1)),
                            );
                            if (picked != null) setState(() => date.value = picked);
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(formatDate(value)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppTextField(label: 'Prescriber name', controller: prescriber),
                const SizedBox(height: 10),
                AppTextField(label: 'Licence number', controller: license),
                const SizedBox(height: 10),
                AppTextField(label: 'Facility', controller: facility),
                const SizedBox(height: 10),
                AppTextField(label: 'Notes', controller: notes, maxLines: 2),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: Text(image == null ? 'Attach prescription image' : 'Image attached'),
                  trailing: image == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => image = null),
                        ),
                  onTap: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1600,
                      imageQuality: 80,
                    );
                    if (picked != null) setState(() => image = File(picked.path));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(S.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                if (patient.text.trim().isEmpty || prescriber.text.trim().isEmpty) return;
                Navigator.pop(context, true);
              },
              child: const Text(S.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(prescriptionsRepositoryProvider);
      // The row is created first so its id can be used in the Storage path.
      final created = await repo.save(
        branchId: branchId,
        patientName: patient.text,
        patientAge: int.tryParse(age.text),
        prescriberName: prescriber.text,
        prescriberLicense: license.text,
        facility: facility.text,
        rxDate: date.value,
        notes: notes.text,
      );
      if (image != null) {
        final path = await repo.uploadImage(
          branchId: branchId,
          prescriptionId: created.id,
          file: image!,
        );
        await repo.save(
          id: created.id,
          branchId: branchId,
          patientName: patient.text,
          patientAge: int.tryParse(age.text),
          prescriberName: prescriber.text,
          prescriberLicense: license.text,
          facility: facility.text,
          rxDate: date.value,
          notes: notes.text,
          imagePath: path,
        );
      }
      ref.invalidate(prescriptionsProvider);
      if (mounted) AppSnackbar.success(context, 'Prescription ${created.rxNo} registered.');
    } catch (error) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _busy = false;

  Future<void> _cancel(Prescription rx) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Cancel prescription?',
      message: '${rx.rxNo} for ${rx.patientName} will be marked cancelled.',
      confirmLabel: 'Cancel prescription',
    );
    if (confirmed != true) return;
    try {
      await ref.read(prescriptionsRepositoryProvider).cancel(rx.id);
      ref.invalidate(prescriptionsProvider);
    } catch (error) {
      if (mounted) AppSnackbar.error(context, AppErrorMapper.from(error).message);
    }
  }

  Future<void> _viewImage(Prescription rx) async {
    if (rx.imagePath == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final url = await ref
        .read(prescriptionsRepositoryProvider)
        .signedImageUrl(rx.imagePath!);
    if (url == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not open the image.')));
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.prescriptions, PermAction.edit);
    final rows = ref.watch(prescriptionsProvider(_status));

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Prescriptions',
              subtitle: 'Register and dispense doctor prescriptions',
              actions: [
                if (canEdit)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PrimaryButton(
                      label: _busy ? 'Working…' : 'Register',
                      icon: Icons.add,
                      width: 140,
                      loading: _busy,
                      onPressed: _add,
                    ),
                  ),
                IconButton(
                  tooltip: S.refresh,
                  onPressed: () => ref.invalidate(prescriptionsProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final status in ['pending', 'dispensed', 'cancelled', null])
                  ChoiceChip(
                    label: Text(status ?? 'All'),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: rows.when(
                data: (list) {
                  if (list.isEmpty) {
                    return EmptyState(
                      message: 'No prescriptions here.',
                      icon: Icons.medical_information_outlined,
                      actionLabel: canEdit ? 'Register' : null,
                      onAction: canEdit ? _add : null,
                    );
                  }
                  return SingleChildScrollView(
                    child: DataTablePlus(
                      columns: const [
                        'Rx no', 'Patient', 'Prescriber', 'Date', 'Status',
                      ],
                      rows: [
                        for (final rx in list)
                          DataTablePlusRow(
                            cells: [
                              rx.rxNo,
                              rx.patientName,
                              rx.prescriberName,
                              rx.rxDate == null ? '—' : formatDate(rx.rxDate!),
                              rx.status.toUpperCase(),
                            ],
                            actions: [
                              if (rx.imagePath != null)
                                IconButton(
                                  tooltip: 'View image',
                                  icon: const Icon(Icons.image_outlined),
                                  onPressed: () => _viewImage(rx),
                                ),
                              if (canEdit && rx.status == 'pending')
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.point_of_sale, size: 16),
                                    label: const Text('New sale'),
                                    onPressed: () =>
                                        context.go('/pos?prescription=${rx.id}'),
                                  ),
                                ),
                              if (canEdit && rx.status == 'pending')
                                IconButton(
                                  tooltip: 'Cancel',
                                  icon: const Icon(Icons.cancel_outlined,
                                      color: AppColors.danger),
                                  onPressed: () => _cancel(rx),
                                ),
                            ],
                          ),
                      ],
                      searchHint: 'Search prescriptions…',
                      exportFileName: 'yusra-prescriptions.csv',
                    ),
                  );
                },
                loading: () => const LoadingSkeleton(lines: 4),
                error: (error, _) => ErrorState(
                  message: AppErrorMapper.from(error).message,
                  onRetry: () => ref.invalidate(prescriptionsProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
