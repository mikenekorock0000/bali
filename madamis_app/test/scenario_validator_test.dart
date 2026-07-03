import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/data/fixed_scenario.dart';
import 'package:madamis_app/models/scenario.dart';
import 'package:madamis_app/models/scenario_config.dart';
import 'package:madamis_app/services/scenario_validator.dart';

void main() {
  final validator = ScenarioValidator();

  test('fixed scenario passes validation', () {
    final scenario = createFixedScenario(playerCount: 4);
    const config = ScenarioConfig(
      genre: '洋館',
      difficulty: '中級',
      estimatedMinutes: 60,
      playerCount: 4,
      theme: 'テスト',
    );
    final report = validator.validate(scenario, config);
    expect(report.passed, isTrue, reason: report.allErrors.join(', '));
  });

  test('clue count helper returns correct values', () {
    expect(ScenarioValidator.clueCountForPlayers(2), 10);
    expect(ScenarioValidator.clueCountForPlayers(4), 15);
    expect(ScenarioValidator.clueCountForPlayers(8), 30);
  });

  test('fails when player count mismatch', () {
    final scenario = createFixedScenario(playerCount: 4);
    const config = ScenarioConfig(
      genre: '洋館',
      difficulty: '中級',
      estimatedMinutes: 60,
      playerCount: 6,
      theme: 'テスト',
    );
    final report = validator.validate(scenario, config);
    expect(report.passed, isFalse);
  });

  test('clue_reachability accepts clues referencing truth method', () {
    final scenario = createFixedScenario(playerCount: 4);
    final clues = [
      ...scenario.clues.where((c) => c.importance != 'critical'),
      ScenarioClue(
        id: 'clue_c1',
        title: '現場の状況',
        content: '被害者の部屋で毒入りの紅茶カップが発見された。犯行時刻22:15の記録あり。',
        type: 'physical',
        importance: 'critical',
      ),
      ScenarioClue(
        id: 'clue_c2',
        title: '遺書の断片',
        content: '遺言状に相続を巡る動機を示す記述が残されていた。',
        type: 'document',
        importance: 'critical',
      ),
    ];
    final patched = Scenario(
      id: scenario.id,
      title: scenario.title,
      genre: scenario.genre,
      synopsis: scenario.synopsis,
      epilogue: scenario.epilogue,
      truth: scenario.truth,
      characters: scenario.characters,
      clues: clues,
      playerCount: scenario.playerCount,
      gameMode: scenario.gameMode,
    );
    const config = ScenarioConfig(
      genre: '洋館',
      difficulty: '中級',
      estimatedMinutes: 60,
      playerCount: 4,
      theme: 'テスト',
    );
    final report = validator.validate(patched, config);
    final clueCheck = report.checks.firstWhere((c) => c.name == 'clue_reachability');
    expect(clueCheck.passed, isTrue, reason: clueCheck.errors.join(', '));
  });
}
