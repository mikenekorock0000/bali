import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/models/game_phase.dart';
import 'package:madamis_app/services/game_engine.dart';

void main() {
  test('creates room and allows players to join', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice');
    final p2 = engine.joinPlayer('Bob');

    expect(p1, isNotNull);
    expect(p2, isNotNull);
    expect(engine.session!.players.length, 2);
  });

  test('assigns unique characters automatically on join', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    engine.joinPlayer('Alice');
    engine.joinPlayer('Bob');

    final assigned = engine.session!.players.map((p) => p.characterId).toList();
    expect(assigned.every((id) => id != null), isTrue);
    expect(assigned.toSet().length, 2);
  });

  test('game starts after players join with auto assignment', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    engine.joinPlayer('Alice');
    engine.joinPlayer('Bob');

    expect(engine.session!.canStart, isTrue);

    final started = engine.startGame();
    expect(started, isTrue);
    expect(engine.session!.phase, GamePhase.synopsis);
  });

  test('player can draw clue during investigation', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice')!;
    engine.joinPlayer('Bob');

    engine.startGame();
    engine.session!.phase = GamePhase.investigation;

    final clue = engine.drawClue(p1.id);
    expect(clue, isNotNull);
    expect(p1.tokensRemaining, 2);
  });

  test('player can transfer clue during investigation', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice')!;
    final p2 = engine.joinPlayer('Bob')!;
    engine.startGame();
    engine.session!.phase = GamePhase.investigation;

    final clue = engine.drawClue(p1.id)!;
    final ok = engine.transferClue(p1.id, p2.id, clue.id);
    expect(ok, isTrue);
    expect(p1.handClues, isEmpty);
    expect(p2.handClues, contains(clue.id));
  });

  test('player can whisper during investigation', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice')!;
    final p2 = engine.joinPlayer('Bob')!;
    engine.startGame();
    engine.session!.phase = GamePhase.investigation;

    final ok = engine.whisper(
      fromId: p1.id,
      toId: p2.id,
      message: '秘密の情報',
    );
    expect(ok, isTrue);
    expect(engine.session!.whispers.length, 1);
    expect(engine.session!.whispers.first.message, '秘密の情報');
  });

  test('connection status updates on disconnect', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice')!;
    engine.setPlayerConnection(p1.id, connected: false);
    expect(p1.connectionStatus, 'disconnected');

    engine.setPlayerConnection(p1.id, connected: true);
    expect(p1.connectionStatus, 'connected');
  });
}
