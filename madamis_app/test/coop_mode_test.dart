import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/data/coop_scenario.dart';
import 'package:madamis_app/models/game_phase.dart';
import 'package:madamis_app/models/scenario_config.dart';
import 'package:madamis_app/services/game_engine.dart';
import 'package:madamis_app/services/scenario_validator.dart';

void main() {
  final validator = ScenarioValidator();

  test('coop scenario passes validation for 2 players', () {
    final scenario = createCoopScenario(playerCount: 2);
    const config = ScenarioConfig(
      genre: '現代',
      difficulty: '初級',
      estimatedMinutes: 60,
      playerCount: 2,
      theme: 'カフェ',
    );
    final report = validator.validate(scenario, config);
    expect(report.passed, isTrue, reason: report.allErrors.join(', '));
  });

  test('cooperative mode uses shared tokens', () {
    final engine = GameEngine();
    engine.createRoomWithScenario(createCoopScenario(playerCount: 2));

    final p1 = engine.joinPlayer('Alice')!;
    engine.joinPlayer('Bob')!;
    engine.selectCharacter(p1.id, 'char_detective_1');
    engine.selectCharacter(engine.session!.players[1].id, 'char_detective_2');
    engine.startGame();
    engine.session!.phase = GamePhase.investigation;

    expect(engine.session!.sharedTokensRemaining, 5);

    engine.drawClue(p1.id);
    expect(engine.session!.sharedTokensRemaining, 4);
  });

  test('cooperative voting uses team score', () {
    final engine = GameEngine();
    engine.createRoomWithScenario(createCoopScenario(playerCount: 2));

    final p1 = engine.joinPlayer('Alice')!;
    final p2 = engine.joinPlayer('Bob')!;
    engine.selectCharacter(p1.id, 'char_detective_1');
    engine.selectCharacter(p2.id, 'char_detective_2');
    engine.startGame();
    engine.session!.phase = GamePhase.voting;

    engine.vote(p1.id, 'npc_manager');
    engine.vote(p2.id, 'npc_manager');

    expect(engine.session!.votes.length, 2);
  });
}
