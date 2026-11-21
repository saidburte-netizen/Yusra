import 'dart:math';

/// Generates a v4 UUID without `dart:io`, so it works on web and Android.
///
/// Flutter's `Random.secure()` is backed by the platform crypto source and is
/// available on every target the app supports. The database accepts these ids
/// for `uuid` columns, which lets a screen know the id before its first insert
/// (needed when an image has to be uploaded into an id-scoped storage folder).
String generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  // RFC 4122 version 4: version bits in byte 6, variant bits in byte 8.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final groups = [
    bytes.sublist(0, 4),
    bytes.sublist(4, 6),
    bytes.sublist(6, 8),
    bytes.sublist(8, 10),
    bytes.sublist(10, 16),
  ];
  return groups.map((group) => group.map(hex).join()).join('-');
}
