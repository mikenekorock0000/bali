enum SavedScenarioSource { asset, local }

class SavedScenarioSummary {
  const SavedScenarioSummary({
    required this.loadKey,
    required this.source,
    required this.title,
    required this.playerCount,
    required this.gameMode,
    required this.genre,
    required this.theme,
    required this.clueCount,
    required this.savedAt,
  });

  final String loadKey;
  final SavedScenarioSource source;
  final String title;
  final int playerCount;
  final String gameMode;
  final String genre;
  final String theme;
  final int clueCount;
  final DateTime? savedAt;

  bool get isCooperative => gameMode == 'cooperative';
  bool get isLocal => source == SavedScenarioSource.local;

  String get modeLabel => isCooperative ? '協力推理' : '対立推理';
}
