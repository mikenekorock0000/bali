import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/scenario.dart';
import '../models/scenario_config.dart';

/// アプリ内で生成したシナリオを端末に永続保存する。
class ScenarioSaveService {
  ScenarioSaveService._();
  static final ScenarioSaveService instance = ScenarioSaveService._();

  Future<Directory> get scenariosDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'scenarios'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<String> save(Scenario scenario, ScenarioConfig config) async {
    final dir = await scenariosDir;
    final slug = _slugify(scenario.title);
    final fileName = 'generated_${config.playerCount}p_$slug.json';
    final path = p.join(dir.path, fileName);

    final payload = {
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'source': 'app',
      'config': config.toJson(),
      'scenario': scenario.toJson(),
    };

    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return path;
  }

  Future<List<String>> listFilePaths() async {
    final dir = await scenariosDir;
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => path.endsWith('.json'))
        .toList()
      ..sort((a, b) => _playerCountFromPath(a).compareTo(_playerCountFromPath(b)));
  }

  Future<Scenario> loadScenario(String filePath) async {
    final json = await _loadEnvelope(filePath);
    return Scenario.fromJson(json['scenario'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> loadEnvelope(String filePath) => _loadEnvelope(filePath);

  Future<Map<String, dynamic>> _loadEnvelope(String filePath) async {
    final raw = await File(filePath).readAsString();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  int _playerCountFromPath(String path) {
    final match = RegExp(r'generated_(\d+)p_').firstMatch(path);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  String _slugify(String title) {
    final normalized = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u3040-\u9fff]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.isEmpty) return 'untitled';
    return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
  }
}

/// CLI・テスト用のシナリオ保存（相対パス）。
String saveScenarioToAssets(Scenario scenario, ScenarioConfig config, {String baseDir = 'assets/scenarios'}) {
  final dir = Directory(baseDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final slug = _slugifyForCli(scenario.title);
  final fileName = 'generated_${config.playerCount}p_$slug.json';
  final path = p.join(dir.path, fileName);

  final payload = {
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'source': 'cli',
    'config': config.toJson(),
    'scenario': scenario.toJson(),
  };

  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  return path;
}

String _slugifyForCli(String title) {
  final normalized = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u3040-\u9fff]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (normalized.isEmpty) return 'untitled';
  return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
}
