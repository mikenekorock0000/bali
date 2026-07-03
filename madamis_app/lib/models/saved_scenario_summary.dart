class SavedScenarioSummary {
  const SavedScenarioSummary({
    required this.assetPath,
    required this.title,
    required this.playerCount,
    required this.gameMode,
    required this.genre,
    required this.theme,
    required this.clueCount,
    required this.savedAt,
  });

  final String assetPath;
  final String title;
  final int playerCount;
  final String gameMode;
  final String genre;
  final String theme;
  final int clueCount;
  final DateTime? savedAt;

  bool get isCooperative => gameMode == 'cooperative';

  String get modeLabel => isCooperative ? '協力推理' : '対立推理';
}
