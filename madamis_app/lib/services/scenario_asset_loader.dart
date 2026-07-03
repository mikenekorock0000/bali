import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/scenario.dart';

class ScenarioAssetLoader {
  ScenarioAssetLoader._();
  static final ScenarioAssetLoader instance = ScenarioAssetLoader._();

  static const _prefix = 'assets/scenarios/generated_';

  Future<List<String>> listAssetPaths() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest
        .listAssets()
        .where((path) => path.startsWith(_prefix) && path.endsWith('.json'))
        .toList()
      ..sort((a, b) => _playerCountFromPath(a).compareTo(_playerCountFromPath(b)));
  }

  Future<Scenario> loadScenario(String assetPath) async {
    final json = await _loadEnvelope(assetPath);
    return Scenario.fromJson(json['scenario'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _loadEnvelope(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  int _playerCountFromPath(String path) {
    final match = RegExp(r'generated_(\d+)p_').firstMatch(path);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}
