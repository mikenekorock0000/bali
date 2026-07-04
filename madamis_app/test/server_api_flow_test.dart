import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/services/game_engine.dart';
import 'package:madamis_app/services/server_service.dart';

/// HTTP経由でプレイヤーWebのボタン操作（参加・確認しました）を再現する統合テスト。
void main() {
  late GameEngine engine;
  late ServerService server;
  late String baseUrl;

  setUp(() async {
    engine = GameEngine();
    engine.createRoom(playerCount: 4);
    server = ServerService(engine: engine);
    await server.start(hostIp: '127.0.0.1', port: 0);
    baseUrl = 'http://127.0.0.1:${server.boundPort}';
  });

  tearDown(() async {
    await server.stop();
    engine.dispose();
  });

  group('player web API flow', () {
    test('join with deviceId blocks duplicate device slots', () async {
      final first = await postJson(
        '$baseUrl/api/players/join',
        {'nickname': 'Alice', 'deviceId': 'device-a'},
      );
      final second = await postJson(
        '$baseUrl/api/players/join',
        {'nickname': 'Alice2', 'deviceId': 'device-a'},
      );

      expect(first['error'], isNull);
      expect(second['error'], isNull);
      expect(second['playerId'], first['playerId']);
      expect(second['token'], first['token']);
      expect(second['reconnected'], isTrue);
      expect(engine.session!.players.length, 1);
    });

    test('synopsis ready advances after all connected players confirm', () async {
      final p1 = await joinPlayer(baseUrl, 'Player1', 'dev-1');
      final p2 = await joinPlayer(baseUrl, 'Player2', 'dev-2');

      final start = await postJson('$baseUrl/api/room/start', {});
      expect(start['error'], isNull);
      expect(start['ok'], isTrue);

      final before1 = await getMe(baseUrl, p1['token'] as String);
      expect(before1['session']['phase'], 'synopsis');

      final ready1 = await markReady(baseUrl, p1['token'] as String, 'synopsis');
      expect(ready1['error'], isNull);
      expect(ready1['ok'], isTrue);

      final mid = await getMe(baseUrl, p1['token'] as String);
      expect(mid['session']['phase'], 'synopsis');
      expect(mid['player']['readyFlags']['synopsis'], isTrue);

      final ready2 = await markReady(baseUrl, p2['token'] as String, 'synopsis');
      expect(ready2['error'], isNull);

      final after = await getMe(baseUrl, p2['token'] as String);
      expect(after['session']['phase'], 'private_reading');
    });

    test('synopsis ready rejects wrong phase', () async {
      final p1 = await joinPlayer(baseUrl, 'Player1', 'dev-1');
      await joinPlayer(baseUrl, 'Player2', 'dev-2');
      await postJson('$baseUrl/api/room/start', {});

      final res = await markReady(baseUrl, p1['token'] as String, 'investigation');
      expect(res['error'], 'Cannot mark ready');

      final me = await getMe(baseUrl, p1['token'] as String);
      expect(me['session']['phase'], 'synopsis');
    });

    test('disconnected player does not block synopsis advance', () async {
      final p1 = await joinPlayer(baseUrl, 'Player1', 'dev-1');
      final p2 = await joinPlayer(baseUrl, 'Player2', 'dev-2');
      await postJson('$baseUrl/api/room/start', {});

      engine.setPlayerConnection(p2['playerId'] as String, connected: false);

      final ready = await markReady(baseUrl, p1['token'] as String, 'synopsis');
      expect(ready['error'], isNull);

      final me = await getMe(baseUrl, p1['token'] as String);
      expect(me['session']['phase'], 'private_reading');
    });
  });
}

Future<Map<String, dynamic>> joinPlayer(
  String baseUrl,
  String nickname,
  String deviceId,
) async {
  final res = await postJson(
    '$baseUrl/api/players/join',
    {'nickname': nickname, 'deviceId': deviceId},
  );
  expect(res['error'], isNull);
  return res;
}

Future<Map<String, dynamic>> getMe(String baseUrl, String token) async {
  return getJson('$baseUrl/api/players/me', token: token);
}

Future<Map<String, dynamic>> markReady(
  String baseUrl,
  String token,
  String phase,
) async {
  return postJson(
    '$baseUrl/api/game/ready',
    {'phase': phase},
    token: token,
  );
}

Future<Map<String, dynamic>> postJson(
  String url,
  Map<String, dynamic> body, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.set('Content-Type', 'application/json');
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
      final payload = utf8.encode(jsonEncode(body));
      request.headers.set('Content-Length', '${payload.length}');
      request.add(payload);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> getJson(String url, {String? token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}
