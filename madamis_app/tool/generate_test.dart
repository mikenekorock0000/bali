#!/usr/bin/env dart
/// AIシナリオ生成のE2Eテスト（環境変数 GEMINI_API_KEY 必須）
///
/// 使い方:
///   export GEMINI_API_KEY=your_key
///   dart run tool/generate_test.dart
///   dart run tool/generate_test.dart --players=2
///   dart run tool/generate_test.dart --players=8 --save
import 'dart:io';

import 'package:madamis_app/config/api_key_source.dart';
import 'package:madamis_app/models/generation_failure.dart';
import 'package:madamis_app/models/generation_progress.dart';
import 'package:madamis_app/models/scenario_config.dart';
import 'package:madamis_app/services/generation_diagnostic_log.dart';
import 'package:madamis_app/services/scenario_generator.dart';
import 'package:madamis_app/services/scenario_save_service.dart';
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
  final progress = GenerationProgress(maxAttempts: 2);

  try {
    final generator = ScenarioGenerator(maxAttempts: 2);
    final scenario = await generator.generate(
      config,
      apiKey: apiKey,
      onProgress: (p) {
        progress
          ..status = p.status
          ..currentStep = p.currentStep
          ..message = p.message
          ..attempt = p.attempt
          ..maxAttempts = p.maxAttempts
          ..errors = p.errors
          ..lastFailure = p.lastFailure
          ..failureHistory = p.failureHistory;
        stdout.writeln('  [${p.currentStep}/8] ${p.message} (試行 ${p.attempt})');
        if (p.lastFailure != null) {
          stdout.writeln('    ⚠ ${p.lastFailure!.locationLabel}: ${p.lastFailure!.code}');
        } else if (p.errors.isNotEmpty) {
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
      final path = saveScenarioToAssets(scenario, config);
      stdout.writeln('   保存: $path');
    }
  } on ScenarioGenerationException catch (e) {
    stopwatch.stop();
    stderr.writeln('');
    stderr.writeln('❌ 生成失敗 (${stopwatch.elapsed.inSeconds}秒)');
    stderr.writeln(formatGenerationFailureReport(progress));
    if (e.failure != null) {
      stderr.writeln('');
      stderr.writeln(e.failure!.summary);
    } else {
      stderr.writeln(e.message);
    }

    final logPath = 'tool/output/generation_logs';
    saveDiagnosticLogToFile(
      directory: logPath,
      config: config,
      progress: progress,
      exceptionMessage: e.message,
    );
    stderr.writeln('');
    stderr.writeln('診断ログ: $logPath');
    exit(1);
  }
}
