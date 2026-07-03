import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/models/scenario.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saved scenario JSON envelope parses to Scenario', () {
    final file = File('assets/scenarios/generated_4p_白銀の密室.json');
    expect(file.existsSync(), isTrue);

    final envelope = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final scenario = Scenario.fromJson(envelope['scenario'] as Map<String, dynamic>);

    expect(scenario.title, '白銀の密室');
    expect(scenario.playerCount, 4);
    expect(scenario.gameMode, 'competitive');
    expect(scenario.characters.where((c) => c.isPlayer).length, 4);
    expect(scenario.clues.length, 15);
    expect(scenario.truth.culpritId, isNotEmpty);
  });
}
