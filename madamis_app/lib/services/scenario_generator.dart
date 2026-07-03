import 'dart:convert';

import 'package:google_generative_ai/google_generative_ai.dart' as genai;
import 'package:uuid/uuid.dart';

import '../config/ai_pipeline_config.dart';
import '../models/generation_failure.dart';
import '../models/generation_progress.dart';
import '../models/scenario.dart';
import '../models/scenario_config.dart';
import 'scenario_auditor.dart';
import 'scenario_validator.dart';

typedef ProgressCallback = void Function(GenerationProgress progress);

class ScenarioGenerator {
  ScenarioGenerator({
    this.maxAttempts = AiPipelineConfig.maxAttempts,
    ScenarioValidator? validator,
    ScenarioAuditor? auditor,
  })  : validator = validator ?? ScenarioValidator(),
        _auditorFactory = auditor != null ? ((_) => auditor) : null;

  final int maxAttempts;
  final ScenarioValidator validator;
  final ScenarioAuditor Function(String apiKey)? _auditorFactory;
  final _uuid = const Uuid();
  late String _apiKey;

  Future<Scenario> generate(
    ScenarioConfig config, {
    required String? apiKey,
    ProgressCallback? onProgress,
  }) async {
    if (apiKey == null || apiKey.isEmpty) {
      final failure = GenerationFailure(
        step: 0,
        phase: GenerationPhase.apiKey,
        code: 'api_key.missing',
        message: 'Gemini APIキーが設定されていません',
      );
      throw ScenarioGenerationException(failure.summary, failure: failure);
    }
    _apiKey = apiKey;

    final creativeModel = _createModel(
      AiPipelineConfig.primaryModel,
      AiPipelineConfig.creativeTemperature,
    );
    final auditModel = _createModel(
      AiPipelineConfig.auditModel,
      AiPipelineConfig.auditTemperature,
    );
    final repairModel = _createModel(
      AiPipelineConfig.auditModel,
      AiPipelineConfig.repairTemperature,
    );
    final auditor = _auditorFactory?.call(apiKey) ?? ScenarioAuditor(apiKey: apiKey);

    final progress = GenerationProgress(maxAttempts: maxAttempts);
    progress.status = GenerationStatus.running;

    ScenarioGenerationException? lastError;
    var previousErrors = <String>[];

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      progress.attempt = attempt;
      progress.errors = [];
      onProgress?.call(progress);

      try {
        final scenarioJson = await _generateMultiStep(
          creativeModel,
          config,
          progress,
          onProgress,
          previousErrors: previousErrors,
        );

        var scenario = _parseScenario(scenarioJson, config);

        // Step 5: Code validation + repair loop
        _setStep(progress, 5, onProgress);
        var validationPassed = false;
        for (var repair = 0; repair <= AiPipelineConfig.maxRepairPasses; repair++) {
          final report = validator.validate(scenario, config, strict: true);
          if (report.passed) {
            validationPassed = true;
            break;
          }

          progress.errors = report.allErrors;
          if (repair == AiPipelineConfig.maxRepairPasses) {
            final failure = GenerationFailure.validation(
              step: 5,
              attempt: attempt,
              errors: report.allErrors,
              repairPass: repair,
              exhaustedRepairs: true,
            );
            progress.recordFailure(failure);
            lastError = ScenarioGenerationException(failure.summary, failure: failure);
            previousErrors = report.allErrors;
            onProgress?.call(progress);
            break;
          }

          _setStep(progress, 5, onProgress, message: '整合性エラーを修復中... (${repair + 1})');
          final repaired = await _repairForErrors(
            repairModel,
            scenario,
            config,
            report.allErrors,
            attempt: attempt,
          );
          scenario = _parseScenario(repaired, config);
        }
        if (!validationPassed) continue;

        // Step 6: AI comprehensive audit
        _setStep(progress, 6, onProgress);
        final audit = await auditor.audit(scenario, config);
        if (!audit.passed) {
          progress.errors = [
            ...audit.issues,
            ...audit.failedCheckNames.map((n) => 'AI監査: $n 不合格'),
          ];
          previousErrors = progress.errors;

          if (attempt <= maxAttempts) {
            _setStep(progress, 6, onProgress, message: '監査指摘を反映して修復中...');
            final repaired = await _repairScenario(
              repairModel,
              scenario,
              config,
              progress.errors,
              auditHint: audit.simulatedPlaythrough,
              attempt: attempt,
              phase: GenerationPhase.auditRepair,
            );
            scenario = _parseScenario(repaired, config);

            final reAudit = await auditor.audit(scenario, config);
            if (!reAudit.passed) {
              final failure = GenerationFailure.audit(
                attempt: attempt,
                issues: reAudit.issues,
                failedCheckNames: reAudit.failedCheckNames,
                afterRepair: true,
              );
              progress.recordFailure(failure);
              lastError = ScenarioGenerationException(failure.summary, failure: failure);
              previousErrors = [
                ...reAudit.issues,
                ...reAudit.failedCheckNames.map((n) => 'AI監査: $n 不合格'),
              ];
              onProgress?.call(progress);
              continue;
            }
          }
        }

        // Step 7: Polish narrative
        _setStep(progress, 7, onProgress);
        final polished = await _polishScenario(auditModel, scenario, config, attempt: attempt);
        scenario = _parseScenario(polished, config);

        final finalReport = validator.validate(scenario, config, strict: true);
        if (!finalReport.passed) {
          final failure = GenerationFailure(
            step: 7,
            phase: GenerationPhase.postPolishValidation,
            code: 'validation.post_polish',
            message: '仕上げ後の整合性チェックに失敗しました',
            details: finalReport.allErrors,
            attempt: attempt,
          );
          progress.recordFailure(failure);
          lastError = ScenarioGenerationException(failure.summary, failure: failure);
          previousErrors = finalReport.allErrors;
          onProgress?.call(progress);
          continue;
        }

        // Step 8: Success
        _setStep(progress, 8, onProgress);
        progress.status = GenerationStatus.success;
        progress.message = 'シナリオ完成！';
        onProgress?.call(progress);
        return scenario;
      } on ScenarioGenerationException catch (e) {
        lastError = e;
        if (e.failure != null) {
          progress.recordFailure(e.failure!);
        } else {
          progress.errors = [e.message];
        }
        previousErrors = progress.errors;
        onProgress?.call(progress);
      } catch (e) {
        final failure = GenerationFailure(
          step: progress.currentStep,
          phase: GenerationPhase.unknown,
          code: 'unknown.error',
          message: '予期しない生成エラーが発生しました',
          details: [e.toString()],
          attempt: attempt,
        );
        progress.recordFailure(failure);
        lastError = ScenarioGenerationException(failure.summary, failure: failure);
        previousErrors = [e.toString()];
        onProgress?.call(progress);
      }
    }

    progress.status = GenerationStatus.failed;
    progress.message = '生成に失敗しました';
    if (lastError?.failure != null) {
      progress.lastFailure ??= lastError!.failure;
    }
    onProgress?.call(progress);
    throw lastError ?? ScenarioGenerationException(
      'シナリオ生成に失敗しました',
      failure: progress.lastFailure,
    );
  }

  genai.GenerativeModel _createModel(String modelName, double temperature) {
    return genai.GenerativeModel(
      model: modelName,
      apiKey: _apiKey,
      generationConfig: genai.GenerationConfig(
        temperature: temperature,
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<Map<String, dynamic>> _generateMultiStep(
    genai.GenerativeModel model,
    ScenarioConfig config,
    GenerationProgress progress,
    ProgressCallback? onProgress, {
    List<String> previousErrors = const [],
  }) async {
    final errorHint = previousErrors.isEmpty
        ? ''
        : '\n\n## 前回の失敗（必ず修正）\n${previousErrors.take(5).map((e) => '- $e').join('\n')}';

    _setStep(progress, 1, onProgress);
    final foundation = await _callJson(
      model,
      _worldPrompt(config, errorHint),
      step: 1,
      phase: GenerationPhase.creativeWorld,
      attempt: progress.attempt,
    );

    _setStep(progress, 2, onProgress);
    final charactersJson = await _callJson(
      model,
      _charactersPrompt(config, foundation, errorHint),
      step: 2,
      phase: GenerationPhase.creativeCharacters,
      attempt: progress.attempt,
    );

    _setStep(progress, 3, onProgress);
    final scriptsJson = await _callJson(
      model,
      _scriptsPrompt(config, foundation, charactersJson, errorHint),
      step: 3,
      phase: GenerationPhase.creativeScripts,
      attempt: progress.attempt,
    );

    _setStep(progress, 4, onProgress);
    final cluesJson = await _callJson(
      model,
      _cluesPrompt(config, foundation, charactersJson, scriptsJson, errorHint),
      step: 4,
      phase: GenerationPhase.creativeClues,
      attempt: progress.attempt,
    );

    return _assembleScenario(foundation, charactersJson, scriptsJson, cluesJson);
  }

  String _worldPrompt(ScenarioConfig config, String errorHint) {
    final isCoop = config.playerCount <= 3;
    final culpritRule = isCoop
        ? '犯人(culpritId)はNPC容疑者(isPlayer:false)の1人。プレイヤーは探偵チーム。'
        : '犯人(culpritId)はプレイヤーキャラ(isPlayer:true)の1人。全員容疑者。';

    return '''
プロのマーダーミステリーライターとして、シナリオの骨格を設計してください。

## 条件
- ジャンル: ${config.genre}
- 難易度: ${config.difficulty}
- プレイ時間: ${config.estimatedMinutes}分
- 人数: ${config.playerCount}人
- テーマ: ${config.theme}
- モード: ${isCoop ? '協力推理' : '対立推理'}
- $culpritRule

## 品質要件
- あらすじ400-700字、後日談150-250字
- 真相解説600-900字
- timelineは5-8イベント、犯行時刻と全員の動きが追えること
- 犯人のアリバイは犯行時刻と矛盾するよう設計（後工程で台本化）

## JSON出力
{
  "title": "タイトル",
  "genre": "${config.genre}",
  "synopsis": "あらすじ",
  "epilogue": "後日談",
  "truth": {
    "culpritId": "char_or_npc_id",
    "crimeDescription": "事件概要",
    "method": "犯行手法",
    "motive": "動機",
    "timeOfCrime": "22:15",
    "location": "犯行場所",
    "explanation": "真相解説"
  },
  "timeline": [
    {"time": "22:00", "event": "出来事", "location": "場所", "characterIds": ["char_1"]}
  ]
}
$errorHint
''';
  }

  String _charactersPrompt(
    ScenarioConfig config,
    Map<String, dynamic> foundation,
    String errorHint,
  ) {
    final isCoop = config.playerCount <= 3;
    final npcRule = isCoop
        ? 'isPlayer:trueを${config.playerCount}人（探偵）。NPC容疑者(isPlayer:false)を最低2人追加。'
        : 'isPlayer:trueを${config.playerCount}人。NPCは不要。';

    return '''
以下の事件骨格に基づき、登場人物を設計してください。
犯人ID: ${(foundation['truth'] as Map)['culpritId']}

## 骨格
${jsonEncode(foundation)}

## ルール
- $npcRule
- 各キャラにユニークなid（char_xxx / npc_xxx）
- publicProfileは100-150字
- privateScriptは次ステップで詳細化するため、ここでは roleOutline のみ

## JSON出力
{
  "characters": [
    {
      "id": "char_1",
      "name": "名前",
      "age": 30,
      "occupation": "職業",
      "publicProfile": "公開プロフィール",
      "isPlayer": true,
      "roleOutline": "この人物の役割概要"
    }
  ]
}
$errorHint
''';
  }

  String _scriptsPrompt(
    ScenarioConfig config,
    Map<String, dynamic> foundation,
    Map<String, dynamic> charactersJson,
    String errorHint,
  ) {
    final culpritId = (foundation['truth'] as Map)['culpritId'];
    return '''
各キャラクターの個人台本を作成してください。

## 骨格
${jsonEncode(foundation)}

## キャラクター
${jsonEncode(charactersJson)}

## ルール
- 犯人($culpritId)のアリバイは犯行時刻 ${(foundation['truth'] as Map)['timeOfCrime']} と両立しないこと
- 犯人以外: 秘密2-3個、ついてよい嘘1-2個、説得力ある動機
- プレイヤーキャラ: objectives 2-3個
- NPC容疑者: objectives は空配列可
- アリバイは「HH:MM-HH:MM 場所と行動」形式

## JSON出力
{
  "privateScripts": {
    "char_1": {
      "role": "役割",
      "relationship": "被害者との関係",
      "secrets": ["秘密1", "秘密2"],
      "allowedLies": ["嘘1"],
      "motive": "動機",
      "alibi": "22:00-22:30 場所と行動",
      "objectives": ["目標1"]
    }
  }
}
$errorHint
''';
  }

  String _cluesPrompt(
    ScenarioConfig config,
    Map<String, dynamic> foundation,
    Map<String, dynamic> charactersJson,
    Map<String, dynamic> scriptsJson,
    String errorHint,
  ) {
    final clueCount = ScenarioValidator.clueCountForPlayers(config.playerCount);
    final critical = 3;
    final important = 4;
    final supplementary = clueCount - critical - important;

    return '''
手がかりと正解ルートを設計してください。

## 骨格
${jsonEncode(foundation)}

## キャラクター
${jsonEncode(charactersJson)}

## 台本
${jsonEncode(scriptsJson)}

## ルール
- 手がかり合計: $clueCount 枚（critical:$critical, important:$important, supplementary:$supplementary）
- critical手がかりだけで犯人 ${(foundation['truth'] as Map)['culpritId']} に到達可能
- critical手がかり（$critical枚）には必ず以下のいずれかを明示すること:
  * 犯行手法「${(foundation['truth'] as Map)['method']}」に関する具体的情報
  * 動機「${(foundation['truth'] as Map)['motive']}」に関する手がかり
  * 犯行時刻 ${(foundation['truth'] as Map)['timeOfCrime']} や犯行場所に関する証拠
- 各手がかりは120-200字、具体的な内容（固有名詞・数値を含む）
- 赤 herring 用 important を2枚以上
- solutionPath.deductionSteps は5-8ステップ

## JSON出力
{
  "clues": [
    {
      "id": "clue_1",
      "title": "タイトル",
      "content": "内容",
      "type": "physical",
      "importance": "critical"
    }
  ],
  "solutionPath": {
    "requiredClueIds": ["clue_1", "clue_2"],
    "deductionSteps": ["推理ステップ1", "推理ステップ2"],
    "redHerringClueIds": ["clue_5"]
  }
}
$errorHint
''';
  }

  Map<String, dynamic> _assembleScenario(
    Map<String, dynamic> foundation,
    Map<String, dynamic> charactersJson,
    Map<String, dynamic> scriptsJson,
    Map<String, dynamic> cluesJson,
  ) {
    final scripts = scriptsJson['privateScripts'] as Map<String, dynamic>? ?? {};
    final characters = (charactersJson['characters'] as List)
        .map((c) {
          final char = Map<String, dynamic>.from(c as Map<String, dynamic>);
          final id = char['id'] as String;
          char.remove('roleOutline');
          char['privateScript'] = scripts[id] ?? _emptyScript();
          return char;
        })
        .toList();

    return {
      'title': foundation['title'],
      'genre': foundation['genre'],
      'synopsis': foundation['synopsis'],
      'epilogue': foundation['epilogue'],
      'truth': foundation['truth'],
      'characters': characters,
      'clues': cluesJson['clues'],
    };
  }

  Map<String, dynamic> _emptyScript() => {
        'role': '',
        'relationship': '',
        'secrets': [],
        'allowedLies': [],
        'motive': '',
        'alibi': '',
        'objectives': [],
      };

  Future<Map<String, dynamic>> _repairForErrors(
    genai.GenerativeModel model,
    Scenario scenario,
    ScenarioConfig config,
    List<String> errors, {
    String auditHint = '',
    required int attempt,
  }) async {
    final clueOnly = errors.every((e) => e.contains('clue_reachability'));
    if (clueOnly) {
      return _repairCluesOnly(model, scenario, errors, attempt: attempt);
    }
    return _repairScenario(
      model,
      scenario,
      config,
      errors,
      auditHint: auditHint,
      attempt: attempt,
      phase: GenerationPhase.repair,
    );
  }

  Future<Map<String, dynamic>> _repairCluesOnly(
    genai.GenerativeModel model,
    Scenario scenario,
    List<String> errors, {
    required int attempt,
  }) async {
    final truth = scenario.truth;
    final critical = scenario.clues.where((c) => c.importance == 'critical').toList();
    final prompt = '''
critical手がかりに犯行関連情報が不足しています。手がかりのみ修正してください。

## 問題
${errors.map((e) => '- $e').join('\n')}

## 真相（参照用・変更不可）
- 犯行手法: ${truth.method}
- 動機: ${truth.motive}
- 犯行時刻: ${truth.timeOfCrime}
- 犯行場所: ${truth.location}
- 犯人ID: ${truth.culpritId}

## 現在のcritical手がかり
${jsonEncode(critical.map((c) => c.toJson()).toList())}

## 修正ルール
- critical手がかりの content を書き換え、各枚に犯行手法・動機・時刻のいずれかを具体的に含める
- id / importance / type / 手がかり総数は変えない
- 他の importance の手がかりも含めた clues 配列全体を返す

## 出力
{ "clues": [ ...全手がかり... ] }
''';

    final result = await _callJson(
      model,
      prompt,
      step: 5,
      phase: GenerationPhase.repair,
      attempt: attempt,
    );
    final json = scenario.toJson();
    json['clues'] = result['clues'];
    return json;
  }

  Future<Map<String, dynamic>> _repairScenario(
    genai.GenerativeModel model,
    Scenario scenario,
    ScenarioConfig config,
    List<String> errors, {
    String auditHint = '',
    required int attempt,
    GenerationPhase phase = GenerationPhase.repair,
  }) async {
    final prompt = '''
以下のマーダーミステリーシナリオJSONに問題があります。修正版を全文出力してください。

## 問題点
${errors.map((e) => '- $e').join('\n')}
${_repairHintsFor(errors)}

${auditHint.isNotEmpty ? '## 推理シミュレーション参考\n$auditHint\n' : ''}

## プレイ人数: ${config.playerCount}人
## モード: ${config.playerCount <= 3 ? '協力推理（犯人はNPC）' : '対立推理（犯人はプレイヤー）'}

## 現在のシナリオ
${jsonEncode(scenario.toJson())}

## 出力
修正済みの完全なシナリオJSON（title, genre, synopsis, epilogue, truth, characters, clues を含む）
''';

    return _callJson(
      model,
      prompt,
      step: phase == GenerationPhase.auditRepair ? 6 : 5,
      phase: phase,
      attempt: attempt,
    );
  }

  Future<Map<String, dynamic>> _polishScenario(
    genai.GenerativeModel model,
    Scenario scenario,
    ScenarioConfig config, {
    required int attempt,
  }) async {
    final prompt = '''
以下のシナリオの文章品質を向上させてください。構造・ID・人数・手がかり数は変えないこと。

## 改善点
- あらすじ・後日談・真相解説を読みやすく演出
- 手がかりの content を具体化（数値・固有名詞を追加）
- キャラクターの secrets / objectives をプレイしやすく

## シナリオ
${jsonEncode(scenario.toJson())}

## 出力
同じJSON構造の完成版
''';

    return _callJson(
      model,
      prompt,
      step: 7,
      phase: GenerationPhase.polish,
      attempt: attempt,
    );
  }

  String _repairHintsFor(List<String> errors) {
    final hints = <String>[];
    if (errors.any((e) => e.contains('clue_reachability'))) {
      hints.add('''
## clue_reachability 修正指示
- critical手がかりの本文に、犯行手法・動機・犯行時刻のいずれかを具体的な固有名詞付きで記述すること
- 「事件」「調査」だけの抽象表現は不可。証拠物・記録・証言など具体的な内容にすること''');
    }
    if (errors.any((e) => e.contains('required_fields'))) {
      hints.add('''
## required_fields 修正指示
- 全プレイヤーキャラに secrets を2個以上、alibi を「HH:MM-HH:MM 場所と行動」形式で記述すること''');
    }
    if (errors.any((e) => e.contains('motive_culprit_match'))) {
      hints.add('''
## motive_culprit_match 修正指示
- 犯人キャラの privateScript.motive を truth.motive と同じテーマ・キーワードを含むよう修正すること''');
    }
    return hints.isEmpty ? '' : hints.join('\n');
  }

  Future<Map<String, dynamic>> _callJson(
    genai.GenerativeModel model,
    String prompt, {
    required int step,
    required GenerationPhase phase,
    required int attempt,
  }) async {
    try {
      final response = await model.generateContent([genai.Content.text(prompt)]);
      final text = response.text;
      if (text == null || text.isEmpty) {
        final failure = GenerationFailure(
          step: step,
          phase: GenerationPhase.apiResponse,
          code: 'api.empty_response',
          message: 'Geminiから空の応答が返されました',
          attempt: attempt,
        );
        throw ScenarioGenerationException(failure.summary, failure: failure);
      }
      return _extractJson(text, step: step, attempt: attempt);
    } on ScenarioGenerationException {
      rethrow;
    } catch (e) {
      final failure = GenerationFailure(
        step: step,
        phase: phase,
        code: 'api.request_failed',
        message: 'Gemini API呼び出しに失敗しました',
        details: [e.toString()],
        attempt: attempt,
      );
      throw ScenarioGenerationException(failure.summary, failure: failure);
    }
  }

  Scenario _parseScenario(Map<String, dynamic> json, ScenarioConfig config, {int attempt = 1, int step = 0}) {
    try {
      final id = _uuid.v4();
      return Scenario(
        id: id,
        title: json['title'] as String? ?? '無題の事件',
        genre: json['genre'] as String? ?? config.genre,
        synopsis: json['synopsis'] as String? ?? '',
        epilogue: json['epilogue'] as String? ?? '',
        truth: ScenarioTruth.fromJson(json['truth'] as Map<String, dynamic>),
        characters: (json['characters'] as List)
            .map((e) => _parseCharacter(e as Map<String, dynamic>))
            .toList(),
        clues: (json['clues'] as List)
            .map((e) => ScenarioClue.fromJson(e as Map<String, dynamic>))
            .toList(),
        playerCount: config.playerCount,
        gameMode: config.playerCount <= 3 ? 'cooperative' : 'competitive',
      );
    } catch (e) {
      final failure = GenerationFailure(
        step: step == 0 ? 0 : step,
        phase: GenerationPhase.scenarioParse,
        code: 'parse.scenario_invalid',
        message: '生成結果をシナリオに変換できませんでした',
        details: [e.toString()],
        attempt: attempt,
      );
      throw ScenarioGenerationException(failure.summary, failure: failure);
    }
  }

  ScenarioCharacter _parseCharacter(Map<String, dynamic> json) {
    return ScenarioCharacter(
      id: json['id'] as String,
      name: json['name'] as String,
      age: _parseInt(json['age'], defaultValue: 30),
      occupation: json['occupation'] as String? ?? '',
      publicProfile: json['publicProfile'] as String? ?? '',
      isPlayer: json['isPlayer'] as bool? ?? true,
      privateScript: PrivateScript.fromJson(
        json['privateScript'] as Map<String, dynamic>,
      ),
    );
  }

  int _parseInt(dynamic value, {required int defaultValue}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  Map<String, dynamic> _extractJson(String text, {required int step, required int attempt}) {
    try {
      var cleaned = text.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceFirst(RegExp(r'^```(?:json)?\n?'), '');
        cleaned = cleaned.replaceFirst(RegExp(r'\n?```$'), '');
      }
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start == -1 || end == -1) {
        final failure = GenerationFailure(
          step: step,
          phase: GenerationPhase.jsonParse,
          code: 'parse.json_not_found',
          message: 'AI応答からJSONを抽出できませんでした',
          attempt: attempt,
        );
        throw ScenarioGenerationException(failure.summary, failure: failure);
      }
      return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
    } on ScenarioGenerationException {
      rethrow;
    } catch (e) {
      final failure = GenerationFailure(
        step: step,
        phase: GenerationPhase.jsonParse,
        code: 'parse.json_invalid',
        message: 'AI応答のJSONが不正です',
        details: [e.toString()],
        attempt: attempt,
      );
      throw ScenarioGenerationException(failure.summary, failure: failure);
    }
  }

  void _setStep(
    GenerationProgress progress,
    int step,
    ProgressCallback? cb, {
    String? message,
  }) {
    progress.currentStep = step;
    progress.message = message ?? GenerationStep.steps[step - 1].message;
    cb?.call(progress);
  }
}
