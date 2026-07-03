import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/data/fixed_scenario.dart';
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
}
