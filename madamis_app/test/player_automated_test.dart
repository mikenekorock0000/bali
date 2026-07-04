import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/services/player_automated_test.dart';

void main() {
  test('isolated automated test covers all player button flows', () async {
    final report = await PlayerAutomatedTest().runIsolated();
    expect(report.steps, isNotEmpty);

    final failed = report.steps.where((s) => !s.passed).toList();
    if (failed.isNotEmpty) {
      fail('Failed steps: ${failed.map((s) => '${s.label}: ${s.detail}').join(', ')}');
    }

    expect(report.allPassed, isTrue);

    final labels = report.steps.map((s) => s.id).toSet();
    expect(labels, containsAll([
      'join_p1',
      'join_p2',
      'join_dup',
      'gm_start',
      'synopsis_p1',
      'synopsis_p2',
      'script_p1',
      'script_p2',
      'draw_clue',
      'reveal_clue',
      'transfer_clue',
      'whisper',
      'accuse_p1',
      'accuse_p2',
      'vote_p1',
      'vote_p2',
      'results',
    ]));
  });
}
