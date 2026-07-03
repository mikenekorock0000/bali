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

  test('game starts after all characters selected', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice')!;
    final p2 = engine.joinPlayer('Bob')!;

    engine.selectCharacter(p1.id, 'char_doctor');
    engine.selectCharacter(p2.id, 'char_niece');

    expect(engine.session!.canStart, isTrue);

    final started = engine.startGame();
    expect(started, isTrue);
    expect(engine.session!.phase, GamePhase.synopsis);
  });

  test('player can draw clue during investigation', () {
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);

    final p1 = engine.joinPlayer('Alice')!;
    final p2 = engine.joinPlayer('Bob')!;

    engine.selectCharacter(p1.id, 'char_doctor');
    engine.selectCharacter(p2.id, 'char_niece');

    engine.startGame();
    engine.session!.phase = GamePhase.investigation;

    final clue = engine.drawClue(p1.id);
    expect(clue, isNotNull);
    expect(p1.tokensRemaining, 2);
  });
}
