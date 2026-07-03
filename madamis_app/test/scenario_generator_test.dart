import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/models/generation_failure.dart';
import 'package:madamis_app/models/scenario_config.dart';
import 'package:madamis_app/services/scenario_generator.dart';

void main() {
  test('generate throws when API key is missing', () async {
    final generator = ScenarioGenerator(maxAttempts: 1);
    expect(
      () => generator.generate(
        const ScenarioConfig(
          genre: '洋館',
          difficulty: '初級',
          estimatedMinutes: 60,
          playerCount: 4,
          theme: 'テスト',
        ),
        apiKey: null,
      ),
      throwsA(
        isA<ScenarioGenerationException>().having(
          (e) => e.failure?.code,
          'failure code',
          'api_key.missing',
        ),
      ),
    );
  });
}
