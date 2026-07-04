import 'dart:async';

import '../models/game_phase.dart';
import '../models/sim_test_step.dart';
import 'game_engine.dart';
import 'player_api_client.dart';
import 'server_service.dart';

typedef SimTestProgress = void Function(SimTestStep step);

/// プレイヤーWebの全ボタン相当操作をAPI経由で検証する自動テスト。
class PlayerAutomatedTest {
  Future<SimTestReport> runIsolated({
    SimTestProgress? onStep,
    int playerCount = 2,
  }) async {
    final startedAt = DateTime.now();
    final steps = <SimTestStep>[];
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);
    final server = ServerService(engine: engine);

    await server.start(hostIp: '127.0.0.1', port: 0);
    final baseUrl = 'http://127.0.0.1:${server.boundPort}';

    try {
      await _runFlow(
        baseUrl: baseUrl,
        engine: engine,
        playerCount: playerCount,
        steps: steps,
        onStep: onStep,
      );
    } finally {
      await server.stop();
      engine.dispose();
    }

    return SimTestReport(
      steps: steps,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
    );
  }

  Future<void> _runFlow({
    required String baseUrl,
    required GameEngine engine,
    required int playerCount,
    required List<SimTestStep> steps,
    SimTestProgress? onStep,
  }) async {
    final p1 = PlayerApiClient(baseUrl);
    final p2 = PlayerApiClient(baseUrl);

    await _step(steps, onStep, 'join_p1', '参加する (P1)', () async {
      final res = await p1.join(nickname: 'SimPlayer1', deviceId: 'sim-auto-1');
      if (res['error'] != null) throw StateError(res['error'].toString());
      if (res['playerId'] == null) throw StateError('playerId missing');
    });

    await _step(steps, onStep, 'join_p2', '参加する (P2)', () async {
      final res = await p2.join(nickname: 'SimPlayer2', deviceId: 'sim-auto-2');
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'join_dup', '同一端末の再参加 (P1)', () async {
      final res = await p1.join(nickname: 'SimPlayer1b', deviceId: 'sim-auto-1');
      if (res['reconnected'] != true) throw StateError('reconnected expected');
      if (engine.session!.players.length != playerCount) {
        throw StateError('player count should stay $playerCount');
      }
    });

    await _step(steps, onStep, 'gm_start', 'ゲーム開始 (GM)', () async {
      final res = await p1.startGame();
      if (res['error'] != null) throw StateError(res['error'].toString());
      if (engine.session!.phase != GamePhase.synopsis) {
        throw StateError('expected synopsis, got ${engine.session!.phase.id}');
      }
    });

    await _step(steps, onStep, 'synopsis_p1', '確認しました (P1)', () async {
      final res = await p1.markReady('synopsis');
      if (res['error'] != null) throw StateError(res['error'].toString());
      final me = await p1.me();
      if (me['player']['readyFlags']['synopsis'] != true) {
        throw StateError('synopsis flag not set');
      }
    });

    await _step(steps, onStep, 'synopsis_p2', '確認しました (P2)', () async {
      final res = await p2.markReady('synopsis');
      if (res['error'] != null) throw StateError(res['error'].toString());
      if (engine.session!.phase != GamePhase.privateReading) {
        throw StateError('expected private_reading');
      }
    });

    await _step(steps, onStep, 'script_p1', '読了しました (P1)', () async {
      final res = await p1.markReady('private_reading');
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'script_p2', '読了しました (P2)', () async {
      final res = await p2.markReady('private_reading');
      if (res['error'] != null) throw StateError(res['error'].toString());
      if (engine.session!.phase != GamePhase.investigation) {
        throw StateError('expected investigation');
      }
    });

    await _step(steps, onStep, 'draw_clue', '手がかりを引く (P1)', () async {
      final res = await p1.drawClue();
      if (res['error'] != null) throw StateError(res['error'].toString());
      if (res['clue'] == null) throw StateError('clue missing');
    });

    await _step(steps, onStep, 'reveal_clue', '全員に公開 (P1)', () async {
      final me = await p1.me();
      final clues = (me['handClues'] as List?) ?? [];
      if (clues.isEmpty) throw StateError('no hand clues');
      final clueId = (clues.first as Map)['id'] as String;
      final res = await p1.revealClue(clueId);
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'draw_transfer', '手がかり取得→譲渡準備 (P1)', () async {
      final res = await p1.drawClue();
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'transfer_clue', '手がかり譲渡 (P1→P2)', () async {
      final me = await p1.me();
      final clues = (me['handClues'] as List?) ?? [];
      if (clues.isEmpty) throw StateError('no hand clues to transfer');
      final clueId = (clues.first as Map)['id'] as String;
      final p2Id = engine.session!.players.firstWhere((p) => p.token == p2.token).id;
      final res = await p1.transferClue(clueId: clueId, toPlayerId: p2Id);
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'whisper', '密談を送る (P1)', () async {
      final p2Id = engine.session!.players.firstWhere((p) => p.token == p2.token).id;
      final res = await p1.whisper(
        toPlayerId: p2Id,
        message: '自動テスト密談',
      );
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    _skipToPhase(engine, GamePhase.accusation);

    await _step(steps, onStep, 'accuse_p1', '推理を発表 (P1)', () async {
      final res = await p1.accuse('自動テスト推理 P1');
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'accuse_p2', '推理を発表 (P2)', () async {
      final res = await p2.accuse('自動テスト推理 P2');
      if (res['error'] != null) throw StateError(res['error'].toString());
      if (engine.session!.phase != GamePhase.voting) {
        throw StateError('expected voting');
      }
    });

    final voteTarget = engine.session!.scenario.playerCharacters.first.id;

    await _step(steps, onStep, 'vote_p1', '投票 (P1)', () async {
      final res = await p1.vote(voteTarget);
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'vote_p2', '投票 (P2)', () async {
      final res = await p2.vote(voteTarget);
      if (res['error'] != null) throw StateError(res['error'].toString());
    });

    await _step(steps, onStep, 'results', '結果フェーズ到達', () async {
      await _waitForPhase(engine, GamePhase.results, timeout: const Duration(seconds: 8));
    });
  }

  void _skipToPhase(GameEngine engine, GamePhase phase) {
    final session = engine.session!;
    session.phase = phase;
    session.phaseTimeoutAt = null;
  }

  Future<void> _waitForPhase(
    GameEngine engine,
    GamePhase phase, {
    required Duration timeout,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (engine.session?.phase == phase) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'timeout waiting for ${phase.id}, got ${engine.session?.phase.id}',
    );
  }

  Future<void> _step(
    List<SimTestStep> steps,
    SimTestProgress? onStep,
    String id,
    String label,
    Future<void> Function() action,
  ) async {
    final sw = Stopwatch()..start();
    try {
      await action();
      sw.stop();
      final step = SimTestStep(
        id: id,
        label: label,
        passed: true,
        durationMs: sw.elapsedMilliseconds,
      );
      steps.add(step);
      onStep?.call(step);
    } catch (e) {
      sw.stop();
      final step = SimTestStep(
        id: id,
        label: label,
        passed: false,
        detail: e.toString(),
        durationMs: sw.elapsedMilliseconds,
      );
      steps.add(step);
      onStep?.call(step);
    }
  }
}
