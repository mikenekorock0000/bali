import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/models/game_phase.dart';
import 'package:madamis_app/services/game_engine.dart';
import 'package:madamis_app/services/player_api_client.dart';
import 'package:madamis_app/services/server_service.dart';

Future<(int exitCode, String stdout, String stderr)> _runNodeCheck(
  String baseUrl,
  String config,
  String step,
) async {
  final process = await Process.start(
    'node',
    ['tool/webview_headless_check.mjs', baseUrl, config, step],
    environment: {'CHROME_PATH': '/usr/bin/google-chrome'},
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  process.stdout.transform(systemEncoding.decoder).listen(stdoutBuffer.write);
  process.stderr.transform(systemEncoding.decoder).listen(stderrBuffer.write);

  var finished = false;
  var exitCode = 1;
  process.exitCode.then((code) {
    exitCode = code;
    finished = true;
  });
  while (!finished) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  return (exitCode, stdoutBuffer.toString(), stderrBuffer.toString());
}

void _disconnectJoinTestPlayer(GameEngine engine) {
  for (final player in engine.session!.players) {
    if (player.nickname == 'WebViewPlayer1') {
      engine.setPlayerConnection(player.id, connected: false);
      return;
    }
  }
}

Future<void> _expectStep(
  String baseUrl,
  String config,
  String step,
  String label,
) async {
  final result = await _runNodeCheck(baseUrl, config, step);
  expect(result.$1, 0, reason: result.$3);
  expect(result.$2, contains('OK $label'));
}

void main() {
  test('headless browser covers webview screen transitions', () async {
    final nodeModules = File('tool/node_modules/puppeteer-core/package.json');
    if (!nodeModules.existsSync()) {
      final install = await Process.run(
        'npm',
        ['install', '--prefix', 'tool', 'puppeteer-core@24.2.0'],
        runInShell: true,
      );
      expect(install.exitCode, 0, reason: install.stderr.toString());
    }

    final engine = GameEngine();
    engine.createRoom(playerCount: 4);
    final server = ServerService(engine: engine);
    await server.start(hostIp: '127.0.0.1', port: 0);
    final baseUrl = 'http://127.0.0.1:${server.boundPort}';

    try {
      await _expectStep(baseUrl, '{}', 'join', 'WebView: 参加する');
      _disconnectJoinTestPlayer(engine);

      final p1 = PlayerApiClient(baseUrl);
      final p2 = PlayerApiClient(baseUrl);
      await p1.join(nickname: 'API_P1', deviceId: 'wv-api-1');
      await p2.join(nickname: 'API_P2', deviceId: 'wv-api-2');
      await p1.startGame();

      final me = await p1.me();
      final config = jsonEncode({
        'p1': {
          'token': p1.token,
          'playerId': me['player']['id'],
        },
      });

      await _expectStep(baseUrl, config, 'synopsis', 'WebView: 確認しました');
      for (var i = 0; i < 20; i++) {
        final state = await p1.me();
        if (state['player']['readyFlags']?['synopsis'] == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await p1.markReady('synopsis');
      await p2.markReady('synopsis');
      expect((await p1.me())['session']['phase'], 'private_reading');

      await _expectStep(baseUrl, config, 'script', 'WebView: 読了しました');
      await p1.markReady('private_reading');
      await p2.markReady('private_reading');
      expect((await p1.me())['session']['phase'], 'investigation');

      await _expectStep(baseUrl, config, 'draw', 'WebView: 手がかりを引く');
      await _expectStep(baseUrl, config, 'reveal', 'WebView: 全員に公開');
      await _expectStep(baseUrl, config, 'transfer', 'WebView: 手がかり譲渡');
      await _expectStep(baseUrl, config, 'whisper', 'WebView: 密談を送る');

      engine.session!.phase = GamePhase.accusation;
      await _expectStep(baseUrl, config, 'accuse', 'WebView: 推理発表');
      await p1.accuse('wv');
      await p2.accuse('wv');

      engine.session!.phase = GamePhase.voting;
      await _expectStep(baseUrl, config, 'vote', 'WebView: 投票');
    } finally {
      await server.stop();
      engine.dispose();
    }
  });
}
