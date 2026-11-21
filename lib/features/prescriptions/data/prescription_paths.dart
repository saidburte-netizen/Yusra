/// Storage path for a prescription image, derived from the generated id so an
/// upload can happen before the row exists and can be retried with the same id.
///
/// Pure Dart so both web and Android use the same path rules and the rules are
/// unit-testable without importing Supabase.
String prescriptionImagePath({
  required String branchId,
  required String prescriptionId,
  String? fileName,
}) {
  final raw = fileName ?? 'prescription.img';
  final dot = raw.lastIndexOf('.');
  final candidate = dot >= 0 ? raw.substring(dot + 1).toLowerCase() : '';
  final letters = RegExp(r'^[a-z0-9]+').firstMatch(candidate)?.group(0) ?? '';
  var extension = letters.isEmpty ? '.img' : '.$letters';
  if (extension.length > 8) extension = '.img';
  final stamp = DateTime.now().microsecondsSinceEpoch;
  return '$branchId/$prescriptionId/$stamp$extension';
}
