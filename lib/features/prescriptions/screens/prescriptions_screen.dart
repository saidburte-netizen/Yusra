import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/dates.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/permissions.dart';
import '../../../core/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets.dart';
import '../../inventory/data/inventory_ids.dart';
import '../../inventory/data/inventory_providers.dart';
import '../data/prescriptions.dart';

class _Draft {
  const _Draft({
    required this.patientName,
    required this.patientAge,
    required this.prescriberName,
    required this.prescriberLicense,
    required this.facility,
    required this.rxDate,
    required this.notes,
    required this.image,
  });

  final String patientName;
  final int? patientAge;
  final String prescriberName;
  final String? prescriberLicense;
  final String? facility;
  final DateTime rxDate;
  final String? notes;
  final XFile? image;
}

class PrescriptionsScreen extends ConsumerStatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  ConsumerState<PrescriptionsScreen> createState() =>
      _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends ConsumerState<PrescriptionsScreen> {
  String? _status = 'pending';
  bool _busy = false;

  Future<_Draft?> _showForm() async {
    final formKey = GlobalKey<FormState>();
    final patient = TextEditingController();
    final age = TextEditingController();
    final prescriber = TextEditingController();
    final license = TextEditingController();
    final facility = TextEditingController();
    final notes = TextEditingController();
    final date = ValueNotifier<DateTime>(nowAddisAbaba());
    XFile? image;

    final result = await showDialog<_Draft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Register prescription'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppTextField(
                    label: 'Patient name',
                    controller: patient,
                    autofocus: true,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter the patient name.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Age',
                          controller: age,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return null;
                            final parsed = int.tryParse(text);
                            if (parsed == null || parsed < 0 || parsed > 120) {
                              return 'Enter an age between 0 and 120.';
                            }
                            return null;
                          },
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
                                lastDate:
                                    DateTime.now().add(const Duration(days: 1)),
                              );
                              if (picked != null) {
                                setState(() => date.value = picked);
                              }
                            },
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(formatDate(value)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AppTextField(
                    label: 'Prescriber name',
                    controller: prescriber,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter the prescriber name.'
                        : null,
                  ),
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
                    title: Text(image == null
                        ? 'Attach prescription image'
                        : 'Image attached'),
                    trailing: image == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => image = null),
                          ),
                    onTap: () async {
                      final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 1600,
                        imageQuality: 80,
                      );
                      if (picked != null) setState(() => image = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(S.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(
                  context,
                  _Draft(
                    patientName: patient.text.trim(),
                    patientAge: int.tryParse(age.text.trim()),
                    prescriberName: prescriber.text.trim(),
                    prescriberLicense: license.text.trim().isEmpty
                        ? null
                        : license.text.trim(),
                    facility: facility.text.trim().isEmpty
                        ? null
                        : facility.text.trim(),
                    rxDate: date.value,
                    notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                    image: image,
                  ),
                );
              },
              child: const Text(S.save),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      patient,
      age,
      prescriber,
      license,
      facility,
      notes,
    ]) {
      controller.dispose();
    }
    return result;
  }

  Future<void> _add() async {
    final branchId = ref.read(branchScopeProvider);
    if (branchId == null) {
      AppSnackbar.error(context, S.chooseBranchFirst);
      return;
    }
    final draft = await _showForm();
    if (draft == null || !mounted) return;

    // The id exists before any network call. If the upload fails, no row has
    // been written and the retry reuses the same id and storage folder.
    final id = generateUuidV4();
    final repo = ref.read(prescriptionsRepositoryProvider);
    String? uploadedPath;

    while (true) {
      setState(() => _busy = true);
      try {
        if (draft.image != null && uploadedPath == null) {
          final bytes = await draft.image!.readAsBytes();
          uploadedPath = await repo.uploadImageBytes(
            branchId: branchId,
            prescriptionId: id,
            bytes: bytes,
            fileName: draft.image!.name,
            contentType: draft.image!.mimeType ?? 'image/jpeg',
          );
        }
        final created = await repo.create(
          id: id,
          branchId: branchId,
          patientName: draft.patientName,
          patientAge: draft.patientAge,
          prescriberName: draft.prescriberName,
          prescriberLicense: draft.prescriberLicense,
          facility: draft.facility,
          rxDate: draft.rxDate,
          notes: draft.notes,
          imagePath: uploadedPath,
        );
        ref.invalidate(prescriptionsProvider);
        if (!mounted) return;
        AppSnackbar.success(
            context, 'Prescription ${created.rxNo} registered.');
        return;
      } catch (error) {
        if (!mounted) return;
        final retry = await _askRetry(AppErrorMapper.from(error).message);
        if (retry != true) return;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<bool?> _askRetry(String message) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Prescription could not be saved'),
          content: Text('$message\n\nNothing was registered. Try again?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(S.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(S.retry),
            ),
          ],
        ),
      );

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
      if (!mounted) return;
      ref.invalidate(prescriptionsProvider);
      AppSnackbar.success(context, 'Prescription cancelled.');
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  Future<void> _viewImage(Prescription rx) async {
    final path = rx.imagePath;
    if (path == null) return;
    try {
      final url =
          await ref.read(prescriptionsRepositoryProvider).signedImageUrl(path);
      final uri = Uri.tryParse(url);
      if (uri == null || !await canLaunchUrl(uri)) {
        throw const AppError('The prescription image could not be opened.');
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) {
        AppSnackbar.error(context, AppErrorMapper.from(error).message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).profile?.role ?? AppRole.cashier;
    final canEdit = can(role, Modules.prescriptions, PermAction.edit);
    // Cashiers attach an Rx while creating a sale; POS owns that permission.
    final canAttachToSale = can(role, Modules.pos, PermAction.edit);
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
                      onPressed: _busy ? null : _add,
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
                for (final status in [
                  'pending',
                  'dispensed',
                  'cancelled',
                  null
                ])
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
                        'Rx no',
                        'Patient',
                        'Prescriber',
                        'Date',
                        'Status',
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
                              if (canAttachToSale && rx.status == 'pending')
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ElevatedButton.icon(
                                    icon: const Icon(Icons.point_of_sale,
                                        size: 16),
                                    label: const Text('New sale'),
                                    onPressed: () => context
                                        .go('/pos?prescription=${rx.id}'),
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
