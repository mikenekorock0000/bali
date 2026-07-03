import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:uuid/uuid.dart';

import '../models/scenario.dart';
import '../models/scenario_config.dart';
import 'scenario_validator.dart';
import 'settings_service.dart';

typedef ProgressCallback = void Function(GenerationProgress progress);

class ScenarioGenerator {
  ScenarioGenerator({
    this.maxAttempts = 5,
    ScenarioValidator? validator,
  }) : validator = validator ?? ScenarioValidator();

  final int maxAttempts;
  final ScenarioValidator validator;
  final _uuid = const Uuid();

  Future<Scenario> generate(
    ScenarioConfig config, {
    ProgressCallback? onProgress,
  }) async {
    final apiKey = SettingsService.instance.apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw ScenarioGenerationException('Gemini APIキーが設定されていません');
    }

    final progress = GenerationProgress(maxAttempts: maxAttempts);
    progress.status = GenerationStatus.running;

    GenerativeModel? model;
    try {
      model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.8,
          responseMimeType: 'application/json',
        ),
      );
    } catch (e) {
      throw ScenarioGenerationException('Gemini初期化失敗: $e');
    }

    ScenarioGenerationException? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      progress.attempt = attempt;
      progress.errors = [];
      onProgress?.call(progress);

      try {
        // Step 1-3: Generate full scenario
        _updateProgress(progress, 1, onProgress);
        final scenarioJson = await _generateScenarioJson(model, config, attempt);

        _updateProgress(progress, 2, onProgress);
        final scenario = _parseScenario(scenarioJson, config);

        _updateProgress(progress, 3, onProgress);

        // Step 4: Code validation
        _updateProgress(progress, 4, onProgress);
        final report = validator.validate(scenario, config);
        if (!report.passed) {
          progress.errors = report.allErrors;
          lastError = ScenarioGenerationException(
            '整合性チェック失敗 (試行 $attempt/$maxAttempts): ${report.allErrors.first}',
          );
          continue;
        }

        // Step 5: AI solvability check
        _updateProgress(progress, 5, onProgress);
        final solvable = await _verifySolvability(model, scenario);
        if (!solvable) {
          progress.errors = ['AI検証: 推理可能なルートが確認できませんでした'];
          lastError = ScenarioGenerationException(
            '正解ルート検証失敗 (試行 $attempt/$maxAttempts)',
          );
          continue;
        }

        // Step 6: Success
        _updateProgress(progress, 6, onProgress);
        progress.status = GenerationStatus.success;
        progress.message = 'シナリオ完成！';
        onProgress?.call(progress);
        return scenario;
      } on ScenarioGenerationException catch (e) {
        lastError = e;
        progress.errors = [e.message];
        onProgress?.call(progress);
      } catch (e) {
        lastError = ScenarioGenerationException('生成エラー: $e');
        progress.errors = [e.toString()];
        onProgress?.call(progress);
      }
    }

    progress.status = GenerationStatus.failed;
    progress.message = '生成に失敗しました';
    onProgress?.call(progress);
    throw lastError ?? ScenarioGenerationException('シナリオ生成に失敗しました');
  }

  void _updateProgress(GenerationProgress progress, int step, ProgressCallback? cb) {
    progress.currentStep = step;
    progress.message = GenerationStep.steps[step - 1].message;
    cb?.call(progress);
  }

  Future<Map<String, dynamic>> _generateScenarioJson(
    GenerativeModel model,
    ScenarioConfig config,
    int attempt,
  ) async {
    final clueCount = ScenarioValidator.clueCountForPlayers(config.playerCount);
    final isCoop = config.playerCount <= 3;
    final retryHint = attempt > 1
        ? '\n\n前回の生成は整合性チェックに失敗しました。アリバイと犯行時刻の矛盾がないこと、'
            'critical手がかりが2枚以上あり犯人特定に到達できることを必ず守ってください。'
        : '';

    final prompt = '''
あなたはプロのマーダーミステリーシナリオライターです。
以下の条件で完全なシナリオをJSON形式で生成してください。

## 条件
- ジャンル: ${config.genre}
- 難易度: ${config.difficulty}
- プレイ時間: ${config.estimatedMinutes}分
- プレイ人数: ${config.playerCount}人
- テーマ: ${config.theme}
- 手がかり数: ${clueCount}枚（critical: 3枚, important: 4枚, supplementary: 残り）
- 言語: 日本語
- モード: ${isCoop ? '協力推理（2-3人、NPC容疑者を追加可）' : '対立推理（全員容疑者）'}

## 必須ルール
1. 犯人はプレイヤーキャラ(${config.playerCount}人)の中の1人だけ
2. アリバイと犯行時刻に矛盾がないこと
3. critical手がかりを組み合わせれば犯人に到達できること
4. 各キャラに秘密2-3個、ついてよい嘘1-2個、動機、アリバイ、目標を設定
5. 犯人以外にも動機を持つキャラ（赤ヘリング）を含める
6. あらすじは300-600字、後日談は100-200字

## JSON形式（この構造を厳守）
{
  "title": "シナリオタイトル",
  "genre": "${config.genre}",
  "synopsis": "共通あらすじ",
  "epilogue": "後日談",
  "truth": {
    "culpritId": "char_xxx",
    "crimeDescription": "事件概要",
    "method": "犯行手法",
    "motive": "動機",
    "timeOfCrime": "22:15",
    "location": "犯行場所",
    "explanation": "真相解説（500字程度）"
  },
  "characters": [
    {
      "id": "char_xxx",
      "name": "名前",
      "age": 30,
      "occupation": "職業",
      "publicProfile": "公開情報",
      "isPlayer": true,
      "privateScript": {
        "role": "役割",
        "relationship": "関係",
        "secrets": ["秘密1", "秘密2"],
        "allowedLies": ["嘘1"],
        "motive": "動機",
        "alibi": "22:00-22:30 場所と行動",
        "objectives": ["目標1"]
      }
    }
  ],
  "clues": [
    {
      "id": "clue_xxx",
      "title": "手がかりタイトル",
      "content": "内容",
      "type": "physical|testimony|document|digital",
      "importance": "critical|important|supplementary"
    }
  ]
}

charactersはisPlayer:trueを${config.playerCount}人。
${isCoop ? 'NPC容疑者(isPlayer:false)を1-2人追加してよい。' : '全員isPlayer:true。'}
$retryHint
''';

    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text;
    if (text == null || text.isEmpty) {
      throw ScenarioGenerationException('Geminiから空の応答');
    }
    return _extractJson(text);
  }

  Future<bool> _verifySolvability(GenerativeModel model, Scenario scenario) async {
    final prompt = '''
以下のマーダーミステリーシナリオについて、プレイヤー視点で推理シミュレーションを行い、
critical/importance手がかりだけで犯人を特定できるか検証してください。

シナリオJSON:
${jsonEncode(scenario.toJson())}

以下のJSON形式のみで回答:
{"solvable": true/false, "reason": "理由"}
''';

    try {
      final response = await model.generateContent([Content.text(prompt)]);
      final json = _extractJson(response.text ?? '{"solvable": false}');
      return json['solvable'] == true;
    } catch (_) {
      return true; // AI check failure doesn't block if code validation passed
    }
  }

  Scenario _parseScenario(Map<String, dynamic> json, ScenarioConfig config) {
    final id = _uuid.v4();
    return Scenario(
      id: id,
      title: json['title'] as String? ?? '無題の事件',
      genre: json['genre'] as String? ?? config.genre,
      synopsis: json['synopsis'] as String? ?? '',
      epilogue: json['epilogue'] as String? ?? '',
      truth: ScenarioTruth.fromJson(json['truth'] as Map<String, dynamic>),
      characters: (json['characters'] as List)
          .map((e) => ScenarioCharacter.fromJson(e as Map<String, dynamic>))
          .toList(),
      clues: (json['clues'] as List)
          .map((e) => ScenarioClue.fromJson(e as Map<String, dynamic>))
          .toList(),
      playerCount: config.playerCount,
      gameMode: config.playerCount <= 3 ? 'cooperative' : 'competitive',
    );
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
      throw ScenarioGenerationException('JSONが見つかりません');
    }
    return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
  }
}

class ScenarioGenerationException implements Exception {
  ScenarioGenerationException(this.message);
  final String message;
  @override
  String toString() => message;
}
