class AppConstants {
  static const String appVersion = '1.1.0+2';
  static const int serverPort = 8080;
  static const int maxPlayers = 8;
  static const int minPlayers = 2;

  static const Map<String, int> phaseTimeoutsSec = {
    'synopsis': 60,
    'private_reading': 180,
    'investigation': 600,
    'discussion': 600,
    'accusation': 60,
    'voting': 120,
    'truth_reveal': 30,
    'epilogue': 30,
  };
}
