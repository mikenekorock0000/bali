import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../models/sim_test_step.dart';
import 'player_api_client.dart';

/// WebView上でプレイヤーWebのボタンを実際にクリックして検証する。
class PlayerWebViewTester {
  PlayerWebViewTester({required this.controller, required this.baseUrl});

  final WebViewController controller;
  final String baseUrl;

  Future<SimTestStep> verifyJoinButton({
    required String deviceId,
    required String nickname,
  }) async {
    return _run('webview_join', 'WebView: 参加する', () async {
      await _loadFresh(deviceId);
      await _setNickname(nickname);
      await _click('btn-join');
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
      await _js('window.__madamisTest.clickSynopsisReady()');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final disabledAfter = await _isDisabled('btn-synopsis-ready');
      if (!disabledAfter) throw StateError('button should be disabled after click');
    });
  }

  Future<SimTestStep> verifyScriptReady({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_script', 'WebView: 読了しました', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-script');
      await _js('window.__madamisTest.clickScriptReady()');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final disabled = await _isDisabled('btn-script-ready');
      if (!disabled) throw StateError('script ready button should disable');
    });
  }

  Future<SimTestStep> verifyInvestigationButtons({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_investigation', 'WebView: 調査ボタン群', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-investigation');
      await _js('window.__madamisTest.clickDraw()');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final drawExists = await _elementExists('btn-draw');
      if (!drawExists) throw StateError('draw button missing');
      await _setWhisperMessage('WebView密談テスト');
      await _js('window.__madamisTest.clickWhisper()');
    });
  }

  Future<SimTestStep> verifyAccuseButton({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_accuse', 'WebView: 推理発表', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-accusation');
      await _js("window.__madamisTest.clickAccuse('WebView推理')");
    });
  }

  Future<SimTestStep> verifyVoteButton({
    required PlayerApiClient client,
    required String deviceId,
  }) async {
    return _run('webview_vote', 'WebView: 投票', () async {
      await _injectSession(client, deviceId);
      await _waitForScreen('screen-voting');
      await _js('window.__madamisTest.clickVoteFirst()');
    });
  }

  Future<void> _loadFresh(String deviceId) async {
    final url = '$baseUrl/join?deviceId=$deviceId&fresh=1';
    await controller.loadRequest(Uri.parse(url));
    await _waitForTestApi();
  }

  Future<void> _injectSession(PlayerApiClient client, String deviceId) async {
    if (client.token == null) throw StateError('client token missing');
    await _loadFresh(deviceId);
    final me = await client.me();
    final playerId = me['player']['id'] as String;
    await _js(
      "window.__madamisTest.injectSession('${client.token}', '$playerId')",
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
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
    for (var i = 0; i < 40; i++) {
      final active = await _js('window.__madamisTest.getActiveScreen()');
      if (active == screenId) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('screen $screenId not active, got ${await _js('window.__madamisTest.getActiveScreen()')}');
  }

  Future<void> _setNickname(String value) async {
    await _js("window.__madamisTest.setNickname(${jsonEncode(value)})");
  }

  Future<void> _setWhisperMessage(String value) async {
    await _js(
      "document.getElementById('whisper-message').value = ${jsonEncode(value)}",
    );
  }

  Future<void> _click(String elementId) async {
    await _js("document.getElementById('$elementId')?.click()");
  }

  Future<bool> _isDisabled(String elementId) async {
    final v = await _js('window.__madamisTest.isButtonDisabled("$elementId")');
    return v == 'true';
  }

  Future<bool> _elementExists(String elementId) async {
    final v = await _js("!!document.getElementById('$elementId')");
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
