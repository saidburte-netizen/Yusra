import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'strings.dart';

/// Requests a device permission and, when denied, shows a friendly message
/// with an "Open settings" action instead of letting a plugin throw a raw
/// platform error into the UI.
Future<bool> ensureDevicePermission(
  BuildContext context,
  Permission permission, {
  required String deniedMessage,
}) async {
  var status = await permission.status;
  if (status.isGranted || status.isLimited) return true;

  if (status.isPermanentlyDenied) {
    if (!context.mounted) return false;
    final open = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(S.permissionNeeded),
        content: Text(deniedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(S.openSettings),
          ),
        ],
      ),
    );
    if (open == true) await openAppSettings();
    return false;
  }

  status = await permission.request();
  if (status.isGranted || status.isLimited) return true;

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deniedMessage),
        action: const SnackBarAction(
          label: S.openSettings,
          onPressed: openAppSettings,
        ),
      ),
    );
  }
  return false;
}
