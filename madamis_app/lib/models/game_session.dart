import 'game_phase.dart';
import 'scenario.dart';

class Player {
  Player({
    required this.id,
    required this.nickname,
    required this.token,
    this.characterId,
    this.connectionStatus = 'connected',
    this.tokensRemaining = 3,
    List<String>? handClues,
    List<String>? publicClues,
    Map<String, bool>? readyFlags,
  })  : handClues = handClues ?? [],
        publicClues = publicClues ?? [],
        readyFlags = readyFlags ?? {};

  final String id;
  String nickname;
  final String token;
  String? characterId;
  String connectionStatus;
  int tokensRemaining;
  List<String> handClues;
  List<String> publicClues;
  Map<String, bool> readyFlags;

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'characterId': characterId,
        'connectionStatus': connectionStatus,
        'tokensRemaining': tokensRemaining,
        'handClues': handClues,
        'publicClues': publicClues,
        'readyFlags': readyFlags,
      };

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      token: json['token'] as String? ?? '',
      characterId: json['characterId'] as String?,
      connectionStatus: json['connectionStatus'] as String? ?? 'connected',
      tokensRemaining: json['tokensRemaining'] as int? ?? 3,
      handClues: (json['handClues'] as List?)?.cast<String>() ?? [],
      publicClues: (json['publicClues'] as List?)?.cast<String>() ?? [],
      readyFlags: (json['readyFlags'] as Map?)?.cast<String, bool>() ?? {},
    );
  }
}

class Vote {
  Vote({
    required this.playerId,
    required this.targetCharacterId,
    required this.timestamp,
  });

  final String playerId;
  final String targetCharacterId;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'targetCharacterId': targetCharacterId,
        'timestamp': timestamp.toIso8601String(),
      };
}

class Accusation {
  Accusation({
    required this.playerId,
    required this.content,
    required this.timestamp,
  });

  final String playerId;
  final String content;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };
}

class ClueTransfer {
  ClueTransfer({
    required this.clueId,
    required this.fromPlayerId,
    required this.toPlayerId,
    required this.timestamp,
  });

  final String clueId;
  final String fromPlayerId;
  final String toPlayerId;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'clueId': clueId,
        'fromPlayerId': fromPlayerId,
        'toPlayerId': toPlayerId,
        'timestamp': timestamp.toIso8601String(),
      };
}

class Whisper {
  Whisper({
    required this.fromPlayerId,
    required this.toPlayerId,
    this.clueId,
    required this.message,
    required this.timestamp,
  });

  final String fromPlayerId;
  final String toPlayerId;
  final String? clueId;
  final String message;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'fromPlayerId': fromPlayerId,
        'toPlayerId': toPlayerId,
        'clueId': clueId,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
      };
}

class GameSession {
  GameSession({
    required this.id,
    required this.roomId,
    required this.scenario,
    this.phase = GamePhase.lobby,
    DateTime? phaseStartedAt,
    DateTime? phaseTimeoutAt,
    List<Player>? players,
    List<String>? deckClues,
    List<String>? globalPublicClues,
    List<Vote>? votes,
    List<Accusation>? accusations,
    List<ClueTransfer>? transfers,
    List<Whisper>? whispers,
    this.startedAt,
    this.isStarted = false,
    this.sharedTokensRemaining,
  })  : phaseStartedAt = phaseStartedAt ?? DateTime.now(),
        phaseTimeoutAt = phaseTimeoutAt,
        players = players ?? [],
        deckClues = deckClues ?? [],
        globalPublicClues = globalPublicClues ?? [],
        votes = votes ?? [],
        accusations = accusations ?? [],
        transfers = transfers ?? [],
        whispers = whispers ?? [];

  final String id;
  final String roomId;
  final Scenario scenario;
  GamePhase phase;
  DateTime phaseStartedAt;
  DateTime? phaseTimeoutAt;
  List<Player> players;
  List<String> deckClues;
  List<String> globalPublicClues;
  List<Vote> votes;
  List<Accusation> accusations;
  List<ClueTransfer> transfers;
  List<Whisper> whispers;
  DateTime? startedAt;
  bool isStarted;
  int? sharedTokensRemaining;

  bool get isCooperative => scenario.gameMode == 'cooperative';

  bool get allCharactersSelected {
    if (players.isEmpty) return false;
    return players.every((p) => p.characterId != null);
  }

  bool get canStart {
    return !isStarted &&
        players.length >= 2 &&
        players.length <= scenario.playerCount &&
        allCharactersSelected;
  }

  Map<String, dynamic> toJson({bool includeTruth = false}) => {
        'id': id,
        'roomId': roomId,
        'scenario': scenario.toJson(includeTruth: includeTruth),
        'phase': phase.id,
        'phaseStartedAt': phaseStartedAt.toIso8601String(),
        'phaseTimeoutAt': phaseTimeoutAt?.toIso8601String(),
        'players': players.map((p) => p.toJson()).toList(),
        'deckClues': deckClues,
        'globalPublicClues': globalPublicClues,
        'votes': votes.map((v) => v.toJson()).toList(),
        'accusations': accusations.map((a) => a.toJson()).toList(),
        'transfers': transfers.map((t) => t.toJson()).toList(),
        'whispers': whispers.map((w) => w.toJson()).toList(),
        'startedAt': startedAt?.toIso8601String(),
        'isStarted': isStarted,
        'canStart': canStart,
        'sharedTokensRemaining': sharedTokensRemaining,
        'gameMode': scenario.gameMode,
      };

  factory GameSession.fromJson(Map<String, dynamic> json) {
    return GameSession(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      scenario: Scenario.fromJson(json['scenario'] as Map<String, dynamic>),
      phase: GamePhase.fromId(json['phase'] as String),
      phaseStartedAt: DateTime.parse(json['phaseStartedAt'] as String),
      phaseTimeoutAt: json['phaseTimeoutAt'] != null
          ? DateTime.parse(json['phaseTimeoutAt'] as String)
          : null,
      players: (json['players'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
      deckClues: (json['deckClues'] as List).cast<String>(),
      globalPublicClues: (json['globalPublicClues'] as List).cast<String>(),
      votes: (json['votes'] as List?)
              ?.map((e) {
                final m = e as Map<String, dynamic>;
                return Vote(
                  playerId: m['playerId'] as String,
                  targetCharacterId: m['targetCharacterId'] as String,
                  timestamp: DateTime.parse(m['timestamp'] as String),
                );
              })
              .toList() ??
          [],
      accusations: (json['accusations'] as List?)
              ?.map((e) {
                final m = e as Map<String, dynamic>;
                return Accusation(
                  playerId: m['playerId'] as String,
                  content: m['content'] as String,
                  timestamp: DateTime.parse(m['timestamp'] as String),
                );
              })
              .toList() ??
          [],
      transfers: (json['transfers'] as List?)
              ?.map((e) {
                final m = e as Map<String, dynamic>;
                return ClueTransfer(
                  clueId: m['clueId'] as String,
                  fromPlayerId: m['fromPlayerId'] as String,
                  toPlayerId: m['toPlayerId'] as String,
                  timestamp: DateTime.parse(m['timestamp'] as String),
                );
              })
              .toList() ??
          [],
      whispers: (json['whispers'] as List?)
              ?.map((e) {
                final m = e as Map<String, dynamic>;
                return Whisper(
                  fromPlayerId: m['fromPlayerId'] as String,
                  toPlayerId: m['toPlayerId'] as String,
                  clueId: m['clueId'] as String?,
                  message: m['message'] as String,
                  timestamp: DateTime.parse(m['timestamp'] as String),
                );
              })
              .toList() ??
          [],
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      isStarted: json['isStarted'] as bool? ?? false,
    );
  }
}
