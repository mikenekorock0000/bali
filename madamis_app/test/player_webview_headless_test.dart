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
      final join = await _runNodeCheck(baseUrl, '{}', 'join');
      expect(join.$1, 0, reason: join.$3);
      expect(join.$2, contains('OK WebView: 参加する'));
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

      final synopsis = await _runNodeCheck(baseUrl, config, 'synopsis');
      expect(synopsis.$1, 0, reason: synopsis.$3);
      expect(synopsis.$2, contains('OK WebView: 確認しました'));
      for (var i = 0; i < 20; i++) {
        final state = await p1.me();
        if (state['player']['readyFlags']?['synopsis'] == true) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await p1.markReady('synopsis');
      await p2.markReady('synopsis');
      expect((await p1.me())['session']['phase'], 'private_reading');

      final script = await _runNodeCheck(baseUrl, config, 'script');
      expect(script.$1, 0, reason: script.$3);
      expect(script.$2, contains('OK WebView: 読了しました'));
      await p1.markReady('private_reading');
      await p2.markReady('private_reading');
      expect((await p1.me())['session']['phase'], 'investigation');

      final investigation = await _runNodeCheck(baseUrl, config, 'investigation');
      expect(investigation.$1, 0, reason: investigation.$3);
      expect(investigation.$2, contains('OK WebView: 調査ボタン群'));

      engine.session!.phase = GamePhase.accusation;
      final accuse = await _runNodeCheck(baseUrl, config, 'accuse');
      expect(accuse.$1, 0, reason: accuse.$3);
      expect(accuse.$2, contains('OK WebView: 推理発表'));
      await p1.accuse('wv');
      await p2.accuse('wv');

      engine.session!.phase = GamePhase.voting;
      final vote = await _runNodeCheck(baseUrl, config, 'vote');
      expect(vote.$1, 0, reason: vote.$3);
      expect(vote.$2, contains('OK WebView: 投票'));
    } finally {
      await server.stop();
      engine.dispose();
    }
  });
}
