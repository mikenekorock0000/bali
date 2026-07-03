import 'dart:async';

import 'package:flutter/services.dart';

class AssetServer {
  AssetServer._();
  static final AssetServer instance = AssetServer._();

  final _cache = <String, String>{};

  Future<String> load(String path) async {
    if (_cache.containsKey(path)) return _cache[path]!;
    final assetPath = path.startsWith('assets/') ? path : 'assets/web/$path';
    final content = await rootBundle.loadString(assetPath);
    _cache[path] = content;
    return content;
  }

  void preloadAll() async {
    for (final file in ['index.html', 'style.css', 'app.js']) {
      await load(file);
    }
  }
}
