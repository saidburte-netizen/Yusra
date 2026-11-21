import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../device_permissions.dart';
import '../strings.dart';
import '../theme/app_colors.dart';

double _scannerDialogWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width - 48).clamp(240.0, 460.0).toDouble();

/// Camera barcode scanner with a keyboard-wedge fallback for desktop cashiers.
class BarcodeScanButton extends StatelessWidget {
  const BarcodeScanButton({
    super.key,
    required this.onDetected,
    this.label = 'Scan barcode',
    this.compact = false,
  });

  final void Function(String code) onDetected;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.barcode_reader, size: 18),
        if (!compact) ...[const SizedBox(width: 8), Text(label)],
      ],
    );
    return compact
        ? IconButton(
            tooltip: label,
            onPressed: () => _open(context),
            icon: const Icon(Icons.barcode_reader, color: AppColors.gold700),
          )
        : OutlinedButton(
            onPressed: () => _open(context),
            child: child,
          );
  }

  Future<void> _open(BuildContext context) async {
    final allowed = await ensureDevicePermission(
      context,
      Permission.camera,
      deniedMessage: S.cameraDenied,
    );
    if (!allowed || !context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => BarcodeScannerDialog(onDetected: onDetected),
    );
  }
}

class BarcodeScannerDialog extends StatefulWidget {
  const BarcodeScannerDialog({super.key, required this.onDetected});

  final void Function(String code) onDetected;

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final MobileScannerController _controller;
  final TextEditingController _manual = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _controller = MobileScannerController();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    widget.onDetected(trimmed);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final height =
        (MediaQuery.sizeOf(context).height - 96).clamp(280.0, 520.0).toDouble();
    return Dialog(
      child: SizedBox(
        width: _scannerDialogWidth(context),
        height: height,
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Camera', icon: Icon(Icons.camera_alt)),
                Tab(text: 'Type code', icon: Icon(Icons.keyboard)),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      final barcodes = capture.barcodes;
                      if (barcodes.isEmpty) return;
                      final value = barcodes.first.rawValue;
                      if (value != null) _finish(value);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextField(
                          controller: _manual,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Barcode',
                            hintText: 'Scan or type the code, then press Enter',
                          ),
                          onSubmitted: _finish,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => _finish(_manual.text),
                          child: const Text(S.confirm),
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
