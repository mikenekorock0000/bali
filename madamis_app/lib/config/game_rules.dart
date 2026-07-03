class GameRules {
  GameRules._();

  static int sharedTokensForPlayers(int count) {
    return switch (count) {
      2 => 5,
      3 => 6,
      _ => 5,
    };
  }

  static int personalTokensForPlayers(int count) => 3;

  static int teamScoreCorrect() => 300;
  static int teamScoreClueBonus() => 20;
  static int competitiveScoreCorrect() => 100;
  static int competitiveScoreClueBonus() => 10;

  static bool isCooperativeMode(String gameMode) => gameMode == 'cooperative';
}
