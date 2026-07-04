import 'package:webview_flutter/webview_flutter.dart';

import '../models/game_phase.dart';
import '../models/sim_test_step.dart';
import 'game_engine.dart';
import 'player_api_client.dart';
import 'player_automated_test.dart';
import 'player_webview_tester.dart';
import 'server_service.dart';

/// API自動テスト + WebViewボタンクリック検証を一括実行する。
class PlayerSimulatorService {
  Future<SimTestReport> runFullSuite({
    required WebViewController webViewController,
    void Function(SimTestStep step)? onStep,
  }) async {
    final startedAt = DateTime.now();
    final steps = <SimTestStep>[];

    void emit(SimTestStep step) {
      steps.add(step);
      onStep?.call(step);
    }

    // Phase 1: API — 全ボタン相当の操作を検証
    await PlayerAutomatedTest().runIsolated(onStep: emit);

    // Phase 2: WebView — 実際のDOMボタンをクリック
    final engine = GameEngine();
    engine.createRoom(playerCount: 4);
    final server = ServerService(engine: engine);
    await server.start(hostIp: '127.0.0.1', port: 0);
    final baseUrl = 'http://127.0.0.1:${server.boundPort}';
    final wv = PlayerWebViewTester(
      controller: webViewController,
      baseUrl: baseUrl,
    );

    try {
      final p1 = PlayerApiClient(baseUrl);
      final p2 = PlayerApiClient(baseUrl);

      emit(await wv.verifyJoinButton(
        deviceId: 'wv-sim-1',
        nickname: 'WebViewPlayer1',
      ));

      await p1.join(nickname: 'API_P1', deviceId: 'wv-api-1');
      await p2.join(nickname: 'API_P2', deviceId: 'wv-api-2');
      await p1.startGame();

      emit(await wv.verifySynopsisReady(
        client: p1,
        deviceId: 'wv-synopsis-1',
      ));
      await p1.markReady('synopsis');
      await p2.markReady('synopsis');

      emit(await wv.verifyScriptReady(
        client: p1,
        deviceId: 'wv-script-1',
      ));
      await p1.markReady('private_reading');
      await p2.markReady('private_reading');

      emit(await wv.verifyInvestigationButtons(
        client: p1,
        deviceId: 'wv-inv-1',
      ));

      engine.session!.phase = GamePhase.accusation;
      emit(await wv.verifyAccuseButton(
        client: p1,
        deviceId: 'wv-acc-1',
      ));
      await p1.accuse('wv');
      await p2.accuse('wv');

      engine.session!.phase = GamePhase.voting;
      emit(await wv.verifyVoteButton(
        client: p1,
        deviceId: 'wv-vote-1',
      ));
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
}
