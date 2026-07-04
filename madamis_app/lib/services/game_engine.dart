import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../config/constants.dart';
import '../config/game_rules.dart';
import '../data/fixed_scenario.dart';
import '../models/game_phase.dart';
import '../models/game_session.dart';
import '../models/scenario.dart';

typedef GameEventCallback = void Function(String type, Map<String, dynamic> data);

class GameEngine {
  GameEngine({this.onEvent});

  GameEventCallback? onEvent;
  final _uuid = const Uuid();
  final _random = Random();

  GameSession? _session;
  Timer? _phaseTimer;

  GameSession? get session => _session;

  String createRoom({int playerCount = 4, Scenario? scenario}) {
    final s = scenario ?? createFixedScenario(playerCount: playerCount);
    final roomId = (_random.nextInt(9000) + 1000).toString();
    final isCoop = GameRules.isCooperativeMode(s.gameMode);
    _session = GameSession(
      id: _uuid.v4(),
      roomId: roomId,
      scenario: s,
      deckClues: s.clues.map((c) => c.id).toList()..shuffle(_random),
      sharedTokensRemaining: isCoop
          ? GameRules.sharedTokensForPlayers(s.playerCount)
          : null,
    );
    return roomId;
  }

  String createRoomWithScenario(Scenario scenario) {
    return createRoom(playerCount: scenario.playerCount, scenario: scenario);
  }

  void restoreSession(GameSession session) {
    _session = session;
    _phaseTimer?.cancel();
    if (session.phaseTimeoutAt != null) {
      final remaining = session.phaseTimeoutAt!.difference(DateTime.now()).inSeconds;
      if (remaining > 0 &&
          session.phase != GamePhase.results &&
          session.phase != GamePhase.end &&
          session.phase != GamePhase.lobby) {
        _startPhaseTimer(remaining);
      }
    }
  }

  Player? joinPlayer(String nickname) {
    final session = _session;
    if (session == null) return null;
    if (session.isStarted) return null;
    if (session.players.length >= session.scenario.playerCount) return null;

    final player = Player(
      id: _uuid.v4(),
      nickname: nickname,
      token: _uuid.v4(),
    );
    session.players.add(player);
    assignRandomCharacter(player.id);
    _emit('player_joined', {'player': player.toJson()});
    return player;
  }

  Player? getPlayerByToken(String token) {
    final session = _session;
    if (session == null) return null;
    for (final p in session.players) {
      if (p.token == token) return p;
    }
    return null;
  }

  Player? getPlayerById(String id) {
    final session = _session;
    if (session == null) return null;
    for (final p in session.players) {
      if (p.id == id) return p;
    }
    return null;
  }

  void setPlayerConnection(String playerId, {required bool connected}) {
    final session = _session;
    if (session == null) return;
    final matches = session.players.where((p) => p.id == playerId);
    if (matches.isEmpty) return;
    final player = matches.first;
    player.connectionStatus = connected ? 'connected' : 'disconnected';
    _emit(connected ? 'player_reconnected' : 'player_left', {
      'player': player.toJson(),
    });
  }

  bool whisper({
    required String fromId,
    required String toId,
    String? clueId,
    required String message,
  }) {
    final session = _session;
    if (session == null || session.phase != GamePhase.investigation) return false;

    final from = session.players.firstWhere((p) => p.id == fromId);
    if (clueId != null && !from.handClues.contains(clueId)) return false;

    session.whispers.add(Whisper(
      fromPlayerId: fromId,
      toPlayerId: toId,
      clueId: clueId,
      message: message,
      timestamp: DateTime.now(),
    ));

    _emit('whisper_sent', {
      'fromPlayerId': fromId,
      'toPlayerId': toId,
      'clueId': clueId,
      'message': message,
    });
    return true;
  }

  bool assignRandomCharacter(String playerId) {
    final session = _session;
    if (session == null || session.isStarted) return false;

    final player = session.players.firstWhere((p) => p.id == playerId);
    if (player.characterId != null) return true;

    final available = session.scenario.playerCharacters
        .where((c) => !session.players.any((p) => p.characterId == c.id))
        .map((c) => c.id)
        .toList();
    if (available.isEmpty) return false;

    final characterId = available[_random.nextInt(available.length)];
    return selectCharacter(playerId, characterId);
  }

  void assignAllCharactersRandomly() {
    final session = _session;
    if (session == null || session.isStarted) return;

    final unassigned = session.players.where((p) => p.characterId == null).toList();
    if (unassigned.isEmpty) return;

    final available = session.scenario.playerCharacters
        .where((c) => !session.players.any((p) => p.characterId == c.id))
        .map((c) => c.id)
        .toList()
      ..shuffle(_random);

    for (var i = 0; i < unassigned.length && i < available.length; i++) {
      selectCharacter(unassigned[i].id, available[i]);
    }
  }

  bool selectCharacter(String playerId, String characterId) {
    final session = _session;
    if (session == null || session.isStarted) return false;

    final taken = session.players.any((p) => p.characterId == characterId);
    if (taken) return false;

    final validChar = session.scenario.characters
        .any((c) => c.id == characterId && c.isPlayer);
    if (!validChar) return false;

    final player = session.players.firstWhere((p) => p.id == playerId);
    player.characterId = characterId;
    _emit('character_selected', {
      'playerId': playerId,
      'characterId': characterId,
    });
    return true;
  }

  bool startGame() {
    final session = _session;
    if (session == null) return false;

    assignAllCharactersRandomly();
    if (!session.canStart) return false;

    session.isStarted = true;
    session.startedAt = DateTime.now();
    _advanceToPhase(GamePhase.synopsis);
    return true;
  }

  bool markReady(String playerId, GamePhase phase) {
    final session = _session;
    if (session == null) return false;

    final player = session.players.firstWhere((p) => p.id == playerId);
    player.readyFlags[phase.id] = true;

    final allReady = session.players.every(
      (p) => p.readyFlags[phase.id] == true,
    );

    if (allReady) {
      _advanceFromCurrentPhase();
    }
    return true;
  }

  ScenarioClue? drawClue(String playerId) {
    final session = _session;
    if (session == null || session.phase != GamePhase.investigation) return null;

    final player = session.players.firstWhere((p) => p.id == playerId);

    if (session.isCooperative) {
      if ((session.sharedTokensRemaining ?? 0) <= 0 || session.deckClues.isEmpty) {
        return null;
      }
      session.sharedTokensRemaining = session.sharedTokensRemaining! - 1;
    } else {
      if (player.tokensRemaining <= 0 || session.deckClues.isEmpty) return null;
      player.tokensRemaining--;
    }

    final clueId = session.deckClues.removeAt(0);
    player.handClues.add(clueId);

    final clue = session.scenario.clues.firstWhere((c) => c.id == clueId);
    _emit('clue_drawn', {
      'playerId': playerId,
      'clue': clue.toJson(),
      'sharedTokensRemaining': session.sharedTokensRemaining,
    });
    return clue;
  }

  bool transferClue(String fromId, String toId, String clueId) {
    final session = _session;
    if (session == null || session.phase != GamePhase.investigation) return false;

    final from = session.players.firstWhere((p) => p.id == fromId);
    final to = session.players.firstWhere((p) => p.id == toId);
    if (!from.handClues.contains(clueId)) return false;

    from.handClues.remove(clueId);
    to.handClues.add(clueId);
    session.transfers.add(ClueTransfer(
      clueId: clueId,
      fromPlayerId: fromId,
      toPlayerId: toId,
      timestamp: DateTime.now(),
    ));
    _emit('clue_transferred', {
      'from': fromId,
      'to': toId,
      'clueId': clueId,
    });
    return true;
  }

  ScenarioClue? revealClue(String playerId, String clueId) {
    final session = _session;
    if (session == null || session.phase != GamePhase.investigation) return null;

    final player = session.players.firstWhere((p) => p.id == playerId);
    if (!player.handClues.contains(clueId)) return null;

    player.handClues.remove(clueId);
    player.publicClues.add(clueId);
    if (!session.globalPublicClues.contains(clueId)) {
      session.globalPublicClues.add(clueId);
    }

    final clue = session.scenario.clues.firstWhere((c) => c.id == clueId);
    _emit('clue_revealed', {
      'playerId': playerId,
      'clue': clue.toJson(),
    });
    return clue;
  }

  bool submitAccusation(String playerId, String content) {
    final session = _session;
    if (session == null || session.phase != GamePhase.accusation) return false;

    session.accusations.add(Accusation(
      playerId: playerId,
      content: content,
      timestamp: DateTime.now(),
    ));

    if (session.accusations.length >= session.players.length) {
      _advanceFromCurrentPhase();
    }
    return true;
  }

  bool vote(String playerId, String targetCharacterId) {
    final session = _session;
    if (session == null || session.phase != GamePhase.voting) return false;

    if (session.votes.any((v) => v.playerId == playerId)) return false;

    session.votes.add(Vote(
      playerId: playerId,
      targetCharacterId: targetCharacterId,
      timestamp: DateTime.now(),
    ));

    _emit('vote_cast', {
      'votedCount': session.votes.length,
      'totalCount': session.players.length,
    });

    if (session.votes.length >= session.players.length) {
      _finishVoting();
    }
    return true;
  }

  void _finishVoting() {
    final session = _session!;
    final culpritId = session.scenario.truth.culpritId;
    final voteCounts = <String, int>{};

    for (final vote in session.votes) {
      voteCounts[vote.targetCharacterId] =
          (voteCounts[vote.targetCharacterId] ?? 0) + 1;
    }

    final List<Map<String, dynamic>> scores;
    final Map<String, dynamic> winner;

    if (session.isCooperative) {
      final teamChoice = _majorityVote(voteCounts);
      final teamCorrect = teamChoice == culpritId;
      final totalClues = session.players.fold<int>(
        0,
        (sum, p) => sum + p.handClues.length + p.publicClues.length,
      );
      final teamScore = (teamCorrect ? GameRules.teamScoreCorrect() : 0) +
          totalClues * GameRules.teamScoreClueBonus();

      scores = session.players
          .map((p) => {
                'playerId': p.id,
                'nickname': p.nickname,
                'voteCorrect': teamCorrect,
                'cluesFound': p.handClues.length + p.publicClues.length,
                'totalScore': teamScore,
                'teamScore': teamScore,
              })
          .toList();

      winner = {
        'type': 'team',
        'teamCorrect': teamCorrect,
        'teamChoice': teamChoice,
        'totalScore': teamScore,
      };
    } else {
      scores = session.players.map((p) {
        final playerVote = session.votes.firstWhere((v) => v.playerId == p.id);
        final correct = playerVote.targetCharacterId == culpritId;
        final cluesFound = p.handClues.length + p.publicClues.length;
        return {
          'playerId': p.id,
          'nickname': p.nickname,
          'voteCorrect': correct,
          'cluesFound': cluesFound,
          'totalScore':
              (correct ? GameRules.competitiveScoreCorrect() : 0) +
                  cluesFound * GameRules.competitiveScoreClueBonus(),
        };
      }).toList();

      winner = scores.reduce(
        (a, b) => (a['totalScore'] as int) > (b['totalScore'] as int) ? a : b,
      );
    }

    _emit('all_voted', {'votes': session.votes.map((v) => v.toJson()).toList()});
    _advanceToPhase(GamePhase.truthReveal);
    _emit('truth_revealed', {
      'truth': session.scenario.truth.toJson(),
      'epilogue': session.scenario.epilogue,
    });

    Future.delayed(const Duration(seconds: 3), () {
      _advanceToPhase(GamePhase.epilogue);
      Future.delayed(const Duration(seconds: 3), () {
        _advanceToPhase(GamePhase.results);
        _emit('results', {
          'scores': scores,
          'culpritId': culpritId,
          'winner': winner,
          'gameMode': session.scenario.gameMode,
        });
      });
    });
  }

  String? _majorityVote(Map<String, int> voteCounts) {
    if (voteCounts.isEmpty) return null;
    return voteCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  void _advanceFromCurrentPhase() {
    final session = _session;
    if (session == null) return;

    final next = switch (session.phase) {
      GamePhase.synopsis => GamePhase.privateReading,
      GamePhase.privateReading => GamePhase.investigation,
      GamePhase.investigation => GamePhase.discussion,
      GamePhase.discussion => GamePhase.accusation,
      GamePhase.accusation => GamePhase.voting,
      GamePhase.voting => GamePhase.truthReveal,
      GamePhase.truthReveal => GamePhase.epilogue,
      GamePhase.epilogue => GamePhase.results,
      GamePhase.results => GamePhase.end,
      _ => null,
    };

    if (next != null) {
      for (final p in session.players) {
        p.readyFlags.remove(session.phase.id);
      }
      _advanceToPhase(next);
    }
  }

  void _advanceToPhase(GamePhase phase) {
    final session = _session;
    if (session == null) return;

    session.phase = phase;
    session.phaseStartedAt = DateTime.now();

    final timeoutSec = AppConstants.phaseTimeoutsSec[phase.id];
    if (timeoutSec != null &&
        phase != GamePhase.results &&
        phase != GamePhase.end) {
      session.phaseTimeoutAt =
          DateTime.now().add(Duration(seconds: timeoutSec));
      _startPhaseTimer(timeoutSec);
    } else {
      session.phaseTimeoutAt = null;
      _phaseTimer?.cancel();
    }

    _emit('phase_changed', {
      'phase': phase.id,
      'phaseLabel': phase.label,
      'timeoutAt': session.phaseTimeoutAt?.toIso8601String(),
    });
  }

  void _startPhaseTimer(int seconds) {
    _phaseTimer?.cancel();
    _phaseTimer = Timer(Duration(seconds: seconds), () {
      final session = _session;
      if (session == null) return;
      if (session.phase == GamePhase.investigation ||
          session.phase == GamePhase.discussion ||
          session.phase == GamePhase.accusation ||
          session.phase == GamePhase.voting) {
        if (session.phase == GamePhase.voting && session.votes.isNotEmpty) {
          _finishVoting();
        } else {
          _advanceFromCurrentPhase();
        }
      } else if (session.phase == GamePhase.synopsis ||
          session.phase == GamePhase.privateReading) {
        _advanceFromCurrentPhase();
      }
    });
  }

  Map<String, dynamic> getPlayerView(String playerId) {
    final session = _session!;
    final player = session.players.firstWhere((p) => p.id == playerId);
    final character = player.characterId != null
        ? session.scenario.characters
            .firstWhere((c) => c.id == player.characterId)
        : null;

    final handClueDetails = player.handClues
        .map((id) => session.scenario.clues.firstWhere((c) => c.id == id))
        .map((c) => c.toJson())
        .toList();

    final publicClueDetails = session.globalPublicClues
        .map((id) => session.scenario.clues.firstWhere((c) => c.id == id))
        .map((c) => c.toJson())
        .toList();

    return {
      'session': {
        'phase': session.phase.id,
        'phaseLabel': session.phase.label,
        'phaseTimeoutAt': session.phaseTimeoutAt?.toIso8601String(),
        'isStarted': session.isStarted,
        'gameMode': session.scenario.gameMode,
        'sharedTokensRemaining': session.sharedTokensRemaining,
        'synopsis': session.scenario.synopsis,
        'epilogue': session.phase.index >= GamePhase.epilogue.index
            ? session.scenario.epilogue
            : null,
        'truth': session.phase.index >= GamePhase.truthReveal.index
            ? session.scenario.truth.toJson()
            : null,
      },
      'player': player.toJson(),
      'character': character?.toJson(),
      'availableCharacters': session.isStarted
          ? []
          : session.scenario.playerCharacters
              .where((c) => !session.players.any((p) => p.characterId == c.id))
              .map((c) => {
                    'id': c.id,
                    'name': c.name,
                    'age': c.age,
                    'occupation': c.occupation,
                    'publicProfile': c.publicProfile,
                  })
              .toList(),
      'handClues': handClueDetails,
      'publicClues': publicClueDetails,
      'players': session.players
          .map((p) {
            final char = p.characterId != null
                ? session.scenario.characters
                    .where((c) => c.id == p.characterId)
                    .map((c) => c.name)
                    .firstOrNull
                : null;
            return {
              'id': p.id,
              'nickname': p.nickname,
              'characterId': p.characterId,
              'characterName': char,
              'connectionStatus': p.connectionStatus,
            };
          })
          .toList(),
      'characters': _voteTargets(session)
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'occupation': c.occupation,
                'isNpc': !c.isPlayer,
              })
          .toList(),
      'otherPlayers': session.players
          .where((p) => p.id != playerId)
          .map((p) => {
                'id': p.id,
                'nickname': p.nickname,
              })
          .toList(),
      'whispers': session.whispers
          .where((w) => w.toPlayerId == playerId)
          .map((w) => w.toJson())
          .toList(),
    };
  }

  List<ScenarioCharacter> _voteTargets(GameSession session) {
    if (session.isCooperative) {
      return session.scenario.characters.where((c) => !c.isPlayer).toList();
    }
    return session.scenario.playerCharacters;
  }

  void _emit(String type, Map<String, dynamic> data) {
    onEvent?.call(type, data);
  }

  void dispose() {
    _phaseTimer?.cancel();
  }
}
