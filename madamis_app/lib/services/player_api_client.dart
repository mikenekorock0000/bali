import 'dart:convert';
import 'dart:io';

class PlayerApiClient {
  PlayerApiClient(this.baseUrl);

  final String baseUrl;
  String? token;

  Future<Map<String, dynamic>> join({
    required String nickname,
    required String deviceId,
  }) async {
    final res = await _post('/api/players/join', {
      'nickname': nickname,
      'deviceId': deviceId,
    });
    if (res['token'] != null) {
      token = res['token'] as String;
    }
    return res;
  }

  Future<Map<String, dynamic>> me() => _get('/api/players/me');

  Future<Map<String, dynamic>> markReady(String phase) =>
      _post('/api/game/ready', {'phase': phase});

  Future<Map<String, dynamic>> drawClue() => _post('/api/game/clue/draw', {});

  Future<Map<String, dynamic>> revealClue(String clueId) =>
      _post('/api/game/clue/reveal', {'clueId': clueId});

  Future<Map<String, dynamic>> transferClue({
    required String clueId,
    required String toPlayerId,
  }) =>
      _post('/api/game/clue/transfer', {
        'clueId': clueId,
        'toPlayerId': toPlayerId,
      });

  Future<Map<String, dynamic>> whisper({
    required String toPlayerId,
    String? clueId,
    required String message,
  }) =>
      _post('/api/game/whisper', {
        'toPlayerId': toPlayerId,
        'clueId': clueId,
        'message': message,
      });

  Future<Map<String, dynamic>> accuse(String content) =>
      _post('/api/game/accuse', {'content': content});

  Future<Map<String, dynamic>> vote(String targetCharacterId) =>
      _post('/api/game/vote', {'targetCharacterId': targetCharacterId});

  Future<Map<String, dynamic>> startGame() => _post('/api/room/start', {});

  Future<Map<String, dynamic>> _get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl$path'));
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

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path'));
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
}
