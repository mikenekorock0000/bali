import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/generation_failure.dart';
import '../models/generation_progress.dart';
import '../models/scenario.dart';
import '../models/scenario_config.dart';

/// 生成失敗時の診断ログを端末に保存する（実機テスト前のデバッグ用）。
class GenerationDiagnosticLog {
  GenerationDiagnosticLog._();
  static final GenerationDiagnosticLog instance = GenerationDiagnosticLog._();

  Future<String> save({
    required ScenarioConfig config,
    required GenerationProgress progress,
    String? exceptionMessage,
  }) async {
    final dir = await _logDir();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final fileName = 'generation_failure_$timestamp.json';
    final path = p.join(dir.path, fileName);

    final payload = {
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'config': config.toJson(),
      'status': progress.status.name,
      'currentStep': progress.currentStep,
      'attempt': progress.attempt,
      'maxAttempts': progress.maxAttempts,
      'message': progress.message,
      if (exceptionMessage != null) 'exception': exceptionMessage,
      if (progress.lastFailure != null) 'lastFailure': progress.lastFailure!.toJson(),
      'failureHistory': progress.failureHistory.map((f) => f.toJson()).toList(),
      'errors': progress.errors,
    };

    await File(path).writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return path;
  }

  Future<Directory> _logDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'generation_logs'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }
}

/// CLI用の診断ログ保存（path_provider不要）。
void saveDiagnosticLogToFile({
  required String directory,
  required ScenarioConfig config,
  required GenerationProgress progress,
  String? exceptionMessage,
}) {
  final dir = Directory(directory);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final path = p.join(dir.path, 'generation_failure_$timestamp.json');
  final payload = {
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'config': config.toJson(),
    'status': progress.status.name,
    'currentStep': progress.currentStep,
    'attempt': progress.attempt,
    'maxAttempts': progress.maxAttempts,
    'message': progress.message,
    if (exceptionMessage != null) 'exception': exceptionMessage,
    if (progress.lastFailure != null) 'lastFailure': progress.lastFailure!.toJson(),
    'failureHistory': progress.failureHistory.map((f) => f.toJson()).toList(),
    'errors': progress.errors,
  };

  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
}

String formatGenerationFailureReport(GenerationProgress progress) {
  final buffer = StringBuffer();
  final failure = progress.lastFailure;
  if (failure != null) {
    buffer.writeln('失敗箇所: ${failure.locationLabel}');
    buffer.writeln('エラーコード: ${failure.code}');
    buffer.writeln('${failure.attemptLabel}: ${failure.message}');
    if (failure.details.isNotEmpty) {
      buffer.writeln('詳細:');
      for (final detail in failure.details.take(8)) {
        buffer.writeln('  - $detail');
      }
      if (failure.details.length > 8) {
        buffer.writeln('  ... 他 ${failure.details.length - 8} 件');
      }
    }
  } else if (progress.errors.isNotEmpty) {
    buffer.writeln('エラー: ${progress.errors.first}');
  }
  if (progress.failureHistory.length > 1) {
    buffer.writeln('');
    buffer.writeln('試行履歴 (${progress.failureHistory.length}件):');
    for (final item in progress.failureHistory) {
      buffer.writeln('  • [試行${item.attempt}] ${item.locationLabel}: ${item.message}');
    }
  }
  return buffer.toString().trim();
}
