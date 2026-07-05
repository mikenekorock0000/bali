import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// プレイヤーWebのHTML/JSがボタンとハンドラを正しく結線しているか静的検証する。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String indexHtml;
  late String appJs;

  setUpAll(() async {
    indexHtml = await rootBundle.loadString('assets/web/index.html');
    appJs = await rootBundle.loadString('assets/web/app.js');
  });

  group('player web assets wiring', () {
    test('synopsis and script ready buttons exist in HTML', () {
      expect(indexHtml, contains('id="btn-synopsis-ready"'));
      expect(indexHtml, contains('id="btn-script-ready"'));
      expect(indexHtml, contains('確認しました'));
      expect(indexHtml, contains('読了しました'));
    });

    test('app.js binds click handlers to ready buttons', () {
      expect(
        appJs,
        contains(
          "document.getElementById('btn-synopsis-ready').addEventListener('click', () => markReady('synopsis'))",
        ),
      );
      expect(
        appJs,
        contains(
          "document.getElementById('btn-script-ready').addEventListener('click', () => markReady('private_reading'))",
        ),
      );
    });

    test('markReady calls API and refreshes state on success', () {
      expect(appJs, contains("await api('POST', '/api/game/ready', { phase })"));
      expect(appJs, contains('if (res.error) return showToast(res.error);'));
      expect(appJs, contains('await refreshState();'));
    });

    test('join sends persistent deviceId', () {
      expect(appJs, contains('madamis_deviceId'));
      expect(appJs, contains('deviceId: getDeviceId()'));
    });

    test('ready button disables after player marks ready', () {
      expect(appJs, contains('function updateReadyButton(phase, isReady)'));
      expect(appJs, contains('btn.disabled = true'));
      expect(appJs, contains('確認済み（他の参加者を待っています）'));
      expect(appJs, contains("updateReadyButton('synopsis', player.readyFlags?.synopsis)"));
    });

    test('player_ready websocket event triggers refresh', () {
      expect(appJs, contains("data.type === 'player_ready'"));
      expect(appJs, contains('refreshState();'));
    });

    test('webview test helpers are exposed', () {
      expect(appJs, contains('window.__madamisTest'));
      expect(appJs, contains('prepareSession'));
      expect(appJs, contains('pumpRefresh'));
      expect(appJs, contains('kickJoin'));
      expect(appJs, contains('kickSynopsisReady'));
      expect(appJs, contains('kickDraw'));
      expect(appJs, contains('kickRevealFirstClue'));
      expect(appJs, contains('kickTransferFirstClue'));
      expect(appJs, contains('kickWhisper'));
      expect(appJs, contains('kickAccuse'));
      expect(appJs, contains('kickVoteFirst'));
      expect(appJs, contains('sentWhisperCount'));
      expect(appJs, contains('hasAccused'));
      expect(appJs, contains('hasVoted'));
      expect(appJs, contains('async clickJoin'));
    });

    test('connectWs clears previous ping interval on reconnect', () {
      expect(appJs, contains('function disconnectWs()'));
      expect(appJs, contains('wsPingInterval'));
      expect(appJs, contains('clearInterval(wsPingInterval)'));
    });

    test('websocket handlers schedule serialized refresh', () {
      expect(appJs, contains('function scheduleRefresh()'));
      expect(appJs, contains('scheduleRefresh();'));
    });

    test('clue reveal and transfer await refreshState', () {
      expect(appJs, contains("await api('POST', '/api/game/clue/reveal'"));
      expect(appJs, contains('else await refreshState();'));
      expect(appJs, contains("await api('POST', '/api/game/clue/transfer'"));
    });
  });
}
