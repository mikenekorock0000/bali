#!/usr/bin/env dart
/// AIシナリオ生成のE2Eテスト（環境変数 GEMINI_API_KEY 必須）
///
/// 使い方:
///   export GEMINI_API_KEY=your_key
///   dart run tool/generate_test.dart
///   dart run tool/generate_test.dart --players=2
import 'dart:io';

import 'package:madamis_app/config/api_key_source.dart';
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
  for (final arg in args) {
    if (arg.startsWith('--players=')) {
      playerCount = int.tryParse(arg.split('=').last) ?? 4;
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
  } on ScenarioGenerationException catch (e) {
    stopwatch.stop();
    stderr.writeln('');
    stderr.writeln('❌ 生成失敗 (${stopwatch.elapsed.inSeconds}秒): $e');
    exit(1);
  }
}
