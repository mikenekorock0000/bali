/// シナリオ生成パイプライン内の失敗箇所を特定するための診断モデル。
class GenerationFailure {
  GenerationFailure({
    required this.step,
    required this.phase,
    required this.code,
    required this.message,
    this.details = const [],
    this.attempt = 1,
    this.repairPass,
    DateTime? occurredAt,
  }) : occurredAt = occurredAt ?? DateTime.now();

  /// 1〜8（GenerationStep）。0 は生成前（APIキー等）。
  final int step;
  final GenerationPhase phase;
  final String code;
  final String message;
  final List<String> details;
  final int attempt;
  final int? repairPass;
  final DateTime occurredAt;

  static const _stepLabels = {
    1: '世界観・事件',
    2: '登場人物',
    3: '個人台本',
    4: '手がかり',
    5: '整合性チェック',
    6: 'AI総合監査',
    7: '仕上げ',
    8: '完成',
  };

  String get stepLabel {
    if (step <= 0) return '準備';
    return _stepLabels[step] ?? '不明';
  }

  String get phaseLabel => phase.label;

  String get locationLabel => step <= 0
      ? phaseLabel
      : 'ステップ$step: $stepLabel / $phaseLabel';

  String get summary => '[$locationLabel] $message';

  String get attemptLabel => repairPass != null
      ? '試行 $attempt（修復パス $repairPass）'
      : '試行 $attempt';

  Map<String, dynamic> toJson() => {
        'step': step,
        'phase': phase.name,
        'code': code,
        'message': message,
        'details': details,
        'attempt': attempt,
        if (repairPass != null) 'repairPass': repairPass,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'stepLabel': stepLabel,
        'phaseLabel': phaseLabel,
      };

  factory GenerationFailure.fromJson(Map<String, dynamic> json) {
    return GenerationFailure(
      step: json['step'] as int? ?? 0,
      phase: GenerationPhase.values.firstWhere(
        (p) => p.name == json['phase'],
        orElse: () => GenerationPhase.unknown,
      ),
      code: json['code'] as String? ?? 'unknown',
      message: json['message'] as String? ?? '',
      details: (json['details'] as List?)?.cast<String>() ?? const [],
      attempt: json['attempt'] as int? ?? 1,
      repairPass: json['repairPass'] as int?,
      occurredAt: DateTime.tryParse(json['occurredAt'] as String? ?? ''),
    );
  }

  static GenerationFailure validation({
    required int step,
    required int attempt,
    required List<String> errors,
    int? repairPass,
    bool exhaustedRepairs = false,
  }) {
    final failedChecks = _extractCheckNames(errors);
    final code = failedChecks.isNotEmpty
        ? 'validation.${failedChecks.first}'
        : 'validation.failed';
    return GenerationFailure(
      step: step,
      phase: exhaustedRepairs ? GenerationPhase.validation : GenerationPhase.repair,
      code: code,
      message: exhaustedRepairs
          ? '整合性チェックが修復上限に達しました'
          : '整合性チェックで問題を検出しました',
      details: errors,
      attempt: attempt,
      repairPass: repairPass,
    );
  }

  static GenerationFailure audit({
    required int attempt,
    required List<String> issues,
    required List<String> failedCheckNames,
    bool afterRepair = false,
  }) {
    final code = failedCheckNames.isNotEmpty
        ? 'audit.${failedCheckNames.first}'
        : 'audit.failed';
    return GenerationFailure(
      step: 6,
      phase: afterRepair ? GenerationPhase.auditRepair : GenerationPhase.audit,
      code: code,
      message: afterRepair
          ? '監査修復後もAI監査に不合格でした'
          : 'AI総合監査に不合格でした',
      details: [
        ...issues,
        ...failedCheckNames.map((n) => 'AI監査: $n 不合格'),
      ],
      attempt: attempt,
    );
  }

  static List<String> _extractCheckNames(List<String> errors) {
    final names = <String>[];
    for (final error in errors) {
      final match = RegExp(r'^\[([^\]]+)\]').firstMatch(error);
      if (match != null) {
        names.add(match.group(1)!);
      }
    }
    return names;
  }
}

enum GenerationPhase {
  apiKey('APIキー'),
  creativeWorld('世界観・事件の生成'),
  creativeCharacters('登場人物の生成'),
  creativeScripts('個人台本の生成'),
  creativeClues('手がかりの生成'),
  validation('整合性チェック'),
  repair('AI修復'),
  audit('AI総合監査'),
  auditRepair('監査指摘の修復'),
  polish('仕上げ'),
  postPolishValidation('仕上げ後の整合性チェック'),
  apiResponse('Gemini API応答'),
  jsonParse('JSON解析'),
  scenarioParse('シナリオ組み立て'),
  unknown('不明');

  const GenerationPhase(this.label);
  final String label;
}

class ScenarioGenerationException implements Exception {
  ScenarioGenerationException(this.message, {this.failure});

  final String message;
  final GenerationFailure? failure;

  @override
  String toString() => failure?.summary ?? message;
}
