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
