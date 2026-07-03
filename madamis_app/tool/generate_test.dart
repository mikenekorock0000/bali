#!/usr/bin/env dart
/// AIシナリオ生成のE2Eテスト（環境変数 GEMINI_API_KEY 必須）
///
/// 使い方:
///   export GEMINI_API_KEY=your_key
///   dart run tool/generate_test.dart
///   dart run tool/generate_test.dart --players=2
///   dart run tool/generate_test.dart --players=8 --save
import 'dart:convert';
import 'dart:io';

import 'package:madamis_app/config/api_key_source.dart';
import 'package:madamis_app/models/scenario.dart';
import 'package:madamis_app/models/scenario_config.dart';
import 'package:madamis_app/services/scenario_generator.dart';
import 'package:madamis_app/services/scenario_validator.dart';

Future<void> main(List<String> args) async {
  final apiKey = ApiKeySource.resolve(null);
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('❌ GEMINI_API_KEY が未設定です');
    stderr.writeln('   export GEMINI_API_KEY=your_key');
    exit(1);
  }

  final source = ApiKeySource.isFromEnvironment(null) ? '環境変数' : 'dart-define';
  stdout.writeln('✓ APIキー読み込み ($source)');

  var playerCount = 4;
  var save = true;
  for (final arg in args) {
    if (arg.startsWith('--players=')) {
      playerCount = int.tryParse(arg.split('=').last) ?? 4;
    } else if (arg == '--no-save') {
      save = false;
    } else if (arg == '--save') {
      save = true;
    }
  }

  final config = ScenarioConfig(
    genre: '洋館',
    difficulty: '中級',
    estimatedMinutes: 60,
    playerCount: playerCount,
    theme: '雪夜の別荘・密室殺人',
  );

  stdout.writeln('▶ 生成開始: ${config.playerCount}人 / ${config.theme}');
  final stopwatch = Stopwatch()..start();

  try {
    final generator = ScenarioGenerator(maxAttempts: 2);
    final scenario = await generator.generate(
      config,
      apiKey: apiKey,
      onProgress: (p) {
        stdout.writeln('  [${p.currentStep}/8] ${p.message} (試行 ${p.attempt})');
        if (p.errors.isNotEmpty) {
          stdout.writeln('    ⚠ ${p.errors.first}');
        }
      },
    );

    stopwatch.stop();
    final report = ScenarioValidator().validate(scenario, config, strict: true);

    stdout.writeln('');
    stdout.writeln('✅ 生成成功 (${stopwatch.elapsed.inSeconds}秒)');
    stdout.writeln('   タイトル: ${scenario.title}');
    stdout.writeln('   キャラ: ${scenario.characters.length}人');
    stdout.writeln('   手がかり: ${scenario.clues.length}枚');
    stdout.writeln('   犯人: ${scenario.truth.culpritId}');
    stdout.writeln('   検証: ${report.passed ? "PASS" : "FAIL"}');
    if (!report.passed) {
      for (final e in report.allErrors) {
        stdout.writeln('   - $e');
      }
      exit(2);
    }

    if (save) {
      final path = saveScenario(scenario, config);
      stdout.writeln('   保存: $path');
    }
  } on ScenarioGenerationException catch (e) {
    stopwatch.stop();
    stderr.writeln('');
    stderr.writeln('❌ 生成失敗 (${stopwatch.elapsed.inSeconds}秒): $e');
    exit(1);
  }
}

String saveScenario(Scenario scenario, ScenarioConfig config) {
  final dir = Directory('assets/scenarios');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final slug = _slugify(scenario.title);
  final fileName = 'generated_${config.playerCount}p_$slug.json';
  final path = '${dir.path}/$fileName';

  final payload = {
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'config': {
      'genre': config.genre,
      'difficulty': config.difficulty,
      'estimatedMinutes': config.estimatedMinutes,
      'playerCount': config.playerCount,
      'theme': config.theme,
    },
    'scenario': scenario.toJson(),
  };

  File(path).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  return path;
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
