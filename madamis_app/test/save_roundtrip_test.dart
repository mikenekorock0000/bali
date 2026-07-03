import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/data/fixed_scenario.dart';
import 'package:madamis_app/models/game_session.dart';

void main() {
  test('GameSession JSON roundtrip for save/resume', () {
    final scenario = createFixedScenario(playerCount: 4);
    final session = GameSession(
      id: 'test-session-id',
      roomId: '1234',
      scenario: scenario,
      isStarted: true,
      deckClues: ['clue_a', 'clue_b'],
    );
    session.players.add(Player(
      id: 'p1',
      nickname: 'Alice',
      token: 'tok1',
      characterId: 'char_doctor',
    ));

    final json = session.toJson(includeTruth: true);
    final restored = GameSession.fromJson(json);

    expect(restored.id, session.id);
    expect(restored.roomId, session.roomId);
    expect(restored.scenario.title, scenario.title);
    expect(restored.players.length, 1);
    expect(restored.isStarted, isTrue);
    expect(restored.deckClues, ['clue_a', 'clue_b']);
  });
}
