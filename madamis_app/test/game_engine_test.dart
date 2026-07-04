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

  test('same device cannot join twice', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice', deviceId: 'device-1');
    final p2 = engine.joinPlayer('Bob', deviceId: 'device-1');

    expect(p1, isNotNull);
    expect(p2, isNotNull);
    expect(p1!.id, p2!.id);
    expect(p2.token, p1.token);
    expect(engine.session!.players.length, 1);
    expect(p2.nickname, 'Bob');
  });

  test('markReady advances when all connected players are ready', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice', deviceId: 'd1')!;
    final p2 = engine.joinPlayer('Bob', deviceId: 'd2')!;
    engine.startGame();

    expect(engine.session!.phase, GamePhase.synopsis);

    engine.markReady(p1.id, GamePhase.synopsis);
    expect(engine.session!.phase, GamePhase.synopsis);

    engine.markReady(p2.id, GamePhase.synopsis);
    expect(engine.session!.phase, GamePhase.privateReading);
  });

  test('markReady ignores disconnected players', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice', deviceId: 'd1')!;
    engine.joinPlayer('Bob', deviceId: 'd2');
    engine.startGame();
    engine.setPlayerConnection(
      engine.session!.players.firstWhere((p) => p.id != p1.id).id,
      connected: false,
    );

    final ok = engine.markReady(p1.id, GamePhase.synopsis);
    expect(ok, isTrue);
    expect(engine.session!.phase, GamePhase.privateReading);
  });

  test('markReady rejects wrong phase', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice')!;
    engine.joinPlayer('Bob');
    engine.startGame();

    final ok = engine.markReady(p1.id, GamePhase.investigation);
    expect(ok, isFalse);
    expect(engine.session!.phase, GamePhase.synopsis);
  });
}
