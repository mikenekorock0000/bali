import 'dart:io';

Future<String?> readAssetFromDisk(String path) async {
  final candidates = [
    'assets/web/$path',
    'madamis_app/assets/web/$path',
  ];
  for (final candidate in candidates) {
    final file = File(candidate);
    if (await file.exists()) {
      return file.readAsString();
    }
  }
  return null;
}
