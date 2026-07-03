import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart' as genai;

import '../config/ai_pipeline_config.dart';
import '../models/scenario.dart';
import '../models/scenario_config.dart';

class AuditCheck {
  AuditCheck({required this.name, required this.passed, this.detail = ''});

  final String name;
  final bool passed;
  final String detail;
}

class AuditReport {
  AuditReport({
    required this.passed,
    required this.checks,
    this.issues = const [],
    this.simulatedPlaythrough = '',
  });

  final bool passed;
  final List<AuditCheck> checks;
  final List<String> issues;
  final String simulatedPlaythrough;

  List<String> get failedCheckNames =>
      checks.where((c) => !c.passed).map((c) => c.name).toList();
}

class ScenarioAuditor {
  ScenarioAuditor({required this.apiKey});

  final String apiKey;

  Future<AuditReport> audit(Scenario scenario, ScenarioConfig config) async {
    final model = genai.GenerativeModel(
      model: AiPipelineConfig.auditModel,
      apiKey: apiKey,
      generationConfig: genai.GenerationConfig(
        temperature: AiPipelineConfig.auditTemperature,
        responseMimeType: 'application/json',
      ),
    );

    final isCoop = config.playerCount <= 3;
    final prompt = '''
あなたはマーダーミステリーの厳格なQA監査官です。
以下のシナリオJSONを、プレイヤー視点で徹底的に検証してください。
不合格項目が1つでもあれば passed は false にしてください。

## プレイ条件
- 人数: ${config.playerCount}人
- 難易度: ${config.difficulty}
- モード: ${isCoop ? '協力推理（犯人はNPC容疑者）' : '対立推理（犯人はプレイヤーの1人）'}
- 想定時間: ${config.estimatedMinutes}分

## 監査項目（すべて必須）
1. solvable: critical+important手がかりのみで犯人を特定できる
2. timelineConsistent: 犯行時刻・アリバイ・eventsに矛盾がない
3. culpritAlibiBroken: 犯人のアリバイは犯行時刻と両立しない
4. clueReachable: 手がかりはデッキから引ける量で、重複・欠落がない
5. redHerringsAdequate: 犯人以外にも説得力ある動機・赤 herring がある
6. lieSafe: 許された嘘がバレても推理可能
7. narrativeQuality: あらすじ・真相解説・後日談が300字以上で破綻していない
8. playableWithinTime: ${config.estimatedMinutes}分プレイで調査・議論が成立する

## シナリオJSON
${jsonEncode(scenario.toJson())}

## 出力形式（JSONのみ）
{
  "passed": true,
  "checks": {
    "solvable": true,
    "timelineConsistent": true,
    "culpritAlibiBroken": true,
    "clueReachable": true,
    "redHerringsAdequate": true,
    "lieSafe": true,
    "narrativeQuality": true,
    "playableWithinTime": true
  },
  "issues": ["問題があれば具体的に"],
  "simulatedPlaythrough": "プレイヤー視点の推理手順（200字以上）"
}
''';

    final response = await model.generateContent([genai.Content.text(prompt)]);
    return _parseAuditResponse(response.text);
  }

  AuditReport _parseAuditResponse(String? text) {
    if (text == null || text.isEmpty) {
      return AuditReport(
        passed: false,
        checks: [AuditCheck(name: 'api_response', passed: false, detail: '空の応答')],
        issues: ['AI監査が空の応答を返しました'],
      );
    }

    try {
      final json = _extractJson(text);
      final checksMap = json['checks'] as Map<String, dynamic>? ?? {};
      final checks = checksMap.entries
          .map((e) => AuditCheck(
                name: e.key,
                passed: e.value == true,
                detail: e.value == true ? '' : '${e.key} 不合格',
              ))
          .toList();

      final issues = (json['issues'] as List?)?.cast<String>() ?? [];
      final passed = json['passed'] == true && checks.every((c) => c.passed);

      return AuditReport(
        passed: passed,
        checks: checks,
        issues: issues,
        simulatedPlaythrough: json['simulatedPlaythrough'] as String? ?? '',
      );
    } catch (e) {
      return AuditReport(
        passed: false,
        checks: [AuditCheck(name: 'parse_error', passed: false, detail: '$e')],
        issues: ['AI監査レスポンスの解析に失敗: $e'],
      );
    }
  }

  Map<String, dynamic> _extractJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\n?'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
    }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1) {
      throw FormatException('JSON not found');
    }
    return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
  }
}
