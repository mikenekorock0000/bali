class ScenarioConfig {
  const ScenarioConfig({
    required this.genre,
    required this.difficulty,
    required this.estimatedMinutes,
    required this.playerCount,
    required this.theme,
  });

  final String genre;
  final String difficulty;
  final int estimatedMinutes;
  final int playerCount;
  final String theme;

  Map<String, dynamic> toJson() => {
        'genre': genre,
        'difficulty': difficulty,
        'estimatedMinutes': estimatedMinutes,
        'playerCount': playerCount,
        'theme': theme,
      };

  static const genres = [
    '洋館',
    '現代',
    '和風',
    'ホラー',
    'ファンタジー',
    'ミステリー',
  ];

  static const difficulties = ['初級', '中級', '上級'];
  static const durations = [30, 60, 90, 120];
}

class GenerationStep {
  const GenerationStep({
    required this.index,
    required this.label,
    required this.message,
  });

  final int index;
  final String label;
  final String message;

  static const steps = [
    GenerationStep(index: 1, label: '世界観・事件', message: '世界観・事件設定を生成中...'),
    GenerationStep(index: 2, label: '登場人物', message: '登場人物を設計中...'),
    GenerationStep(index: 3, label: '個人台本', message: '秘密・アリバイ・目標を生成中...'),
    GenerationStep(index: 4, label: '手がかり', message: '手がかりと正解ルートを構築中...'),
    GenerationStep(index: 5, label: '整合性チェック', message: '整合性チェック中...'),
    GenerationStep(index: 6, label: 'AI総合監査', message: '推理シミュレーション・品質監査中...'),
    GenerationStep(index: 7, label: '仕上げ', message: '文章・演出を磨いています...'),
    GenerationStep(index: 8, label: '完成', message: 'シナリオ完成！'),
  ];
}

enum GenerationStatus { idle, running, success, failed }

class GenerationProgress {
  GenerationProgress({
    this.status = GenerationStatus.idle,
    this.currentStep = 0,
    this.message = '',
    this.attempt = 1,
    this.maxAttempts = 5,
    this.errors = const [],
  });

  GenerationStatus status;
  int currentStep;
  String message;
  int attempt;
  int maxAttempts;
  List<String> errors;

  double get progress {
    if (status == GenerationStatus.success) return 1.0;
    if (currentStep == 0) return 0.0;
    return currentStep / GenerationStep.steps.length;
  }
}
