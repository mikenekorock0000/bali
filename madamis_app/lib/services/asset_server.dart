import 'package:flutter/services.dart';

import 'asset_server_disk_stub.dart'
    if (dart.library.io) 'asset_server_disk_io.dart';

class AssetServer {
  AssetServer._();
  static final AssetServer instance = AssetServer._();

  final _cache = <String, String>{};

  Future<String> load(String path) async {
    if (_cache.containsKey(path)) return _cache[path]!;
    final assetPath = path.startsWith('assets/') ? path : 'assets/web/$path';
    String? content;
    try {
      content = await rootBundle.loadString(assetPath);
    } catch (_) {
      content = await readAssetFromDisk(path);
    }
    if (content == null) {
      throw StateError('Asset not found: $path');
    }
    _cache[path] = content;
    return content;
  }

  void preloadAll() async {
    for (final file in ['index.html', 'style.css', 'app.js']) {
      await load(file);
    }
  }
}
