import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../models/sim_test_step.dart';
import 'player_api_client.dart';

/// WebView上でプレイヤーWebのボタンを実際にクリックして検証する。
///
/// Android WebView の [runJavaScriptReturningResult] は Promise を待てないため、
/// JS 側は kick* で非同期処理を開始し、Dart 側で pumpRefresh + ポーリングする。
class PlayerWebViewTester {
  PlayerWebViewTester({
    required this.controller,
    required this.baseUrl,
    void Function(String url)? onPageFinished,
  }) {
    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          if (_pageLoadCompleter != null && !_pageLoadCompleter!.isCompleted) {
            _pageLoadCompleter!.complete();
          }
          onPageFinished?.call(url);
        },
      ),
    );
  }

  final WebViewController controller;
  final String baseUrl;
  Completer<void>? _pageLoadCompleter;

  Future<SimTestStep> verifyJoinButton({
    required String deviceId,
    required String nickname,
  }) async {
    return _run('webview_join', 'WebView: 参加する', () async {
      await _loadFresh(deviceId);
      await _kick(
        'window.__madamisTest.kickJoin(${jsonEncode(nickname)})',
      );
      await _waitForScreen('screen-waiting');
    });
  }

  Future<SimTestStep> verifySynopsisReady({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_synopsis', 'WebView: 確認しました', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-synopsis');
      final disabledBefore = await _isDisabled('btn-synopsis-ready');
      if (disabledBefore) throw StateError('button already disabled');
      await _kick('window.__madamisTest.kickSynopsisReady()');
      await _waitForButtonDisabled('btn-synopsis-ready');
    });
  }

  Future<SimTestStep> verifyScriptReady({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_script', 'WebView: 読了しました', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-script');
      await _kick('window.__madamisTest.kickScriptReady()');
      await _waitForButtonDisabled('btn-script-ready');
    });
  }

  Future<SimTestStep> verifyDrawClue({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_draw', 'WebView: 手がかりを引く', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-investigation');
      final before = await _handClueCount();
      await _kick('window.__madamisTest.kickDraw()');
      await _waitForHandClueCount(before + 1);
    });
  }

  Future<SimTestStep> verifyRevealClue({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_reveal', 'WebView: 全員に公開', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-investigation');
      if (await _handClueCount() == 0) {
        await _kick('window.__madamisTest.kickDraw()');
        await _waitForHandClueCount(1);
      }
      final publicBefore = await _publicClueCount();
      await _kick('window.__madamisTest.kickRevealFirstClue()');
      await _waitForPublicClueCount(publicBefore + 1);
    });
  }

  Future<SimTestStep> verifyTransferClue({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_transfer', 'WebView: 手がかり譲渡', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-investigation');
      if (await _handClueCount() == 0) {
        await _kick('window.__madamisTest.kickDraw()');
        await _waitForHandClueCount(1);
      }
      final before = await _handClueCount();
      await _kick('window.__madamisTest.kickTransferFirstClue()');
      await _waitForHandClueCount(before - 1);
    });
  }

  Future<SimTestStep> verifyWhisperButton({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_whisper', 'WebView: 密談を送る', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-investigation');
      final before = await _sentWhisperCount();
      await _kick(
        'window.__madamisTest.kickWhisper(${jsonEncode('WebView密談テスト')})',
      );
      await _waitForSentWhisperCount(before + 1, client: client);
    });
  }

  Future<SimTestStep> verifyAccuseButton({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_accuse', 'WebView: 推理発表', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-accusation');
      await _kick(
        "window.__madamisTest.kickAccuse(${jsonEncode('WebView推理')})",
      );
      await _waitForPlayerFlag(client, hasAccused: true);
    });
  }

  Future<SimTestStep> verifyVoteButton({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_vote', 'WebView: 投票', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-voting');
      await _kick('window.__madamisTest.kickVoteFirst()');
      await _waitForPlayerFlag(client, hasVoted: true);
    });
  }

  Future<void> _loadFresh(String deviceId) async {
    _pageLoadCompleter = Completer<void>();
    final url = '$baseUrl/join?deviceId=$deviceId&fresh=1';
    await controller.loadRequest(Uri.parse(url));
    await _pageLoadCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw StateError('page load timeout: $url'),
    );
    await _waitForTestApi();
  }

  Future<void> _injectSession(PlayerApiClient client, String deviceId) async {
    if (client.token == null) throw StateError('client token missing');
    await _loadFresh(deviceId);
    final me = await client.me();
    final playerId = me['player']['id'] as String;
    await _js(
      'window.__madamisTest.prepareSession(${jsonEncode(client.token)}, ${jsonEncode(playerId)})',
    );
    await _pumpAndDelay();
  }

  Future<void> _waitForTestApi() async {
    for (var i = 0; i < 30; i++) {
      final ready = await _js('typeof window.__madamisTest !== "undefined"');
      if (ready == 'true') return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('__madamisTest not available');
  }

  Future<void> _waitForScreen(String screenId) async {
    for (var i = 0; i < 60; i++) {
      await _pumpAndDelay();
      final active = await _js('window.__madamisTest.getActiveScreen()');
      if (active == screenId) return;
    }
    final active = await _js('window.__madamisTest.getActiveScreen()');
    final state = await _js('window.__madamisTest.getStateJson()');
    throw StateError(
      'screen $screenId not active, got $active (state: $state)',
    );
  }

  Future<void> _waitForButtonDisabled(String elementId) async {
    for (var i = 0; i < 40; i++) {
      await _pumpAndDelay();
      if (await _isDisabled(elementId)) return;
    }
    throw StateError('button $elementId should be disabled');
  }

  Future<int> _handClueCount() async {
    final v = await _js('String(window.__madamisTest.handClueCount())');
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<int> _publicClueCount() async {
    final v = await _js('String(window.__madamisTest.publicClueCount())');
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<int> _sentWhisperCount() async {
    final v = await _js('String(window.__madamisTest.sentWhisperCount())');
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<void> _waitForHandClueCount(int expected) async {
    for (var i = 0; i < 60; i++) {
      await _pumpAndDelay();
      if (await _handClueCount() == expected) return;
    }
    throw StateError(
      'expected $expected hand clues, got ${await _handClueCount()}',
    );
  }

  Future<void> _waitForPublicClueCount(int expected) async {
    for (var i = 0; i < 60; i++) {
      await _pumpAndDelay();
      if (await _publicClueCount() == expected) return;
    }
    throw StateError(
      'expected $expected public clues, got ${await _publicClueCount()}',
    );
  }

  Future<void> _waitForSentWhisperCount(
    int expected, {
    required PlayerApiClient client,
  }) async {
    for (var i = 0; i < 40; i++) {
      await _pumpAndDelay();
      if (await _sentWhisperCount() >= expected) return;
      final me = await client.me();
      final count = me['player']['sentWhispersCount'] as int? ?? 0;
      if (count >= expected) return;
    }
    throw StateError(
      'expected >= $expected sent whispers, got ${await _sentWhisperCount()}',
    );
  }

  Future<void> _waitForPlayerFlag(
    PlayerApiClient client, {
    bool? hasAccused,
    bool? hasVoted,
  }) async {
    for (var i = 0; i < 40; i++) {
      await _pumpAndDelay();
      if (hasAccused == true && await _jsBool('window.__madamisTest.hasAccused()')) {
        return;
      }
      if (hasVoted == true && await _jsBool('window.__madamisTest.hasVoted()')) {
        return;
      }
      final me = await client.me();
      final player = me['player'] as Map<String, dynamic>;
      if (hasAccused == true && player['hasAccused'] == true) return;
      if (hasVoted == true && player['hasVoted'] == true) return;
    }
    if (hasAccused == true) {
      throw StateError('expected player.hasAccused');
    }
    if (hasVoted == true) {
      throw StateError('expected player.hasVoted');
    }
  }

  Future<void> _kick(String code) async {
    await _js(code);
    await _pumpAndDelay();
  }

  Future<void> _pumpAndDelay() async {
    await _js('window.__madamisTest.pumpRefresh()');
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  Future<bool> _isDisabled(String elementId) async {
    final v = await _js('window.__madamisTest.isButtonDisabled("$elementId")');
    return v == 'true';
  }

  Future<bool> _jsBool(String code) async {
    final v = await _js(code);
    return v == 'true';
  }

  Future<String?> _js(String code) async {
    final result = await controller.runJavaScriptReturningResult(code);
    if (result == null) return null;
    final text = result.toString();
    if (text.startsWith('"') && text.endsWith('"')) {
      return text.substring(1, text.length - 1);
    }
    return text;
  }

  Future<SimTestStep> _run(
    String id,
    String label,
    Future<void> Function() action,
  ) async {
    final sw = Stopwatch()..start();
    try {
      await action();
      sw.stop();
      return SimTestStep(
        id: id,
        label: label,
        passed: true,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return SimTestStep(
        id: id,
        label: label,
        passed: false,
        detail: e.toString(),
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }
}
