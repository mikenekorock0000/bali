import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/saved_scenario_summary.dart';
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

  Future<List<SavedScenarioSummary>> listSummaries() async {
    final paths = await listAssetPaths();
    final summaries = <SavedScenarioSummary>[];
    for (final path in paths) {
      try {
        summaries.add(await _loadSummary(path));
      } catch (_) {}
    }
    return summaries;
  }

  Future<Scenario> loadScenario(String assetPath) async {
    final json = await _loadEnvelope(assetPath);
    return Scenario.fromJson(json['scenario'] as Map<String, dynamic>);
  }

  Future<SavedScenarioSummary> _loadSummary(String assetPath) async {
    final json = await _loadEnvelope(assetPath);
    final config = json['config'] as Map<String, dynamic>? ?? {};
    final scenario = json['scenario'] as Map<String, dynamic>;
    final clues = scenario['clues'] as List? ?? [];

    return SavedScenarioSummary(
      assetPath: assetPath,
      title: scenario['title'] as String? ?? '無題',
      playerCount: scenario['playerCount'] as int? ?? config['playerCount'] as int? ?? 0,
      gameMode: scenario['gameMode'] as String? ?? 'competitive',
      genre: scenario['genre'] as String? ?? config['genre'] as String? ?? '',
      theme: config['theme'] as String? ?? '',
      clueCount: clues.length,
      savedAt: _parseSavedAt(json['savedAt'] as String?),
    );
  }

  Future<Map<String, dynamic>> _loadEnvelope(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  DateTime? _parseSavedAt(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  int _playerCountFromPath(String path) {
    final match = RegExp(r'generated_(\d+)p_').firstMatch(path);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}
