import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/saved_scenario_summary.dart';
import '../models/scenario.dart';
import 'scenario_asset_loader.dart';
import 'scenario_save_service.dart';

/// バンドル済みアセットと端末保存シナリオをまとめて一覧・読込する。
class SavedScenarioRepository {
  SavedScenarioRepository._();
  static final SavedScenarioRepository instance = SavedScenarioRepository._();

  Future<List<SavedScenarioSummary>> listSummaries() async {
    final assetSummaries = await _listAssetSummaries();
    final localSummaries = await _listLocalSummaries();
    final merged = [...assetSummaries, ...localSummaries];
    merged.sort((a, b) {
      final playerCmp = a.playerCount.compareTo(b.playerCount);
      if (playerCmp != 0) return playerCmp;
      return (b.savedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.savedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    });
    return merged;
  }

  Future<Scenario> loadScenario(SavedScenarioSummary summary) async {
    return switch (summary.source) {
      SavedScenarioSource.asset =>
        ScenarioAssetLoader.instance.loadScenario(summary.loadKey),
      SavedScenarioSource.local =>
        ScenarioSaveService.instance.loadScenario(summary.loadKey),
    };
  }

  Future<List<SavedScenarioSummary>> _listAssetSummaries() async {
    final paths = await ScenarioAssetLoader.instance.listAssetPaths();
    final summaries = <SavedScenarioSummary>[];
    for (final path in paths) {
      try {
        summaries.add(await _summaryFromAsset(path));
      } catch (_) {}
    }
    return summaries;
  }

  Future<List<SavedScenarioSummary>> _listLocalSummaries() async {
    final paths = await ScenarioSaveService.instance.listFilePaths();
    final summaries = <SavedScenarioSummary>[];
    for (final path in paths) {
      try {
        summaries.add(await _summaryFromLocal(path));
      } catch (_) {}
    }
    return summaries;
  }

  Future<SavedScenarioSummary> _summaryFromAsset(String assetPath) async {
    final json = await rootBundle.loadString(assetPath);
    return _summaryFromEnvelope(
      loadKey: assetPath,
      source: SavedScenarioSource.asset,
      envelope: _decode(json),
    );
  }

  Future<SavedScenarioSummary> _summaryFromLocal(String filePath) async {
    final envelope = await ScenarioSaveService.instance.loadEnvelope(filePath);
    return _summaryFromEnvelope(
      loadKey: filePath,
      source: SavedScenarioSource.local,
      envelope: envelope,
    );
  }

  SavedScenarioSummary _summaryFromEnvelope({
    required String loadKey,
    required SavedScenarioSource source,
    required Map<String, dynamic> envelope,
  }) {
    final config = envelope['config'] as Map<String, dynamic>? ?? {};
    final scenario = envelope['scenario'] as Map<String, dynamic>;
    final clues = scenario['clues'] as List? ?? [];

    return SavedScenarioSummary(
      loadKey: loadKey,
      source: source,
      title: scenario['title'] as String? ?? '無題',
      playerCount: scenario['playerCount'] as int? ?? config['playerCount'] as int? ?? 0,
      gameMode: scenario['gameMode'] as String? ?? 'competitive',
      genre: scenario['genre'] as String? ?? config['genre'] as String? ?? '',
      theme: config['theme'] as String? ?? '',
      clueCount: clues.length,
      savedAt: _parseSavedAt(envelope['savedAt'] as String?),
    );
  }

  Map<String, dynamic> _decode(String raw) {
    return (const JsonDecoder().convert(raw)) as Map<String, dynamic>;
  }

  DateTime? _parseSavedAt(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
