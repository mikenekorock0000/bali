import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/constants.dart';
import '../models/game_phase.dart';
import '../services/asset_server.dart';
import '../services/game_engine.dart';

class ServerService {
  ServerService({required this.engine});

  final GameEngine engine;
  HttpServer? _server;
  String? _hostIp;
  final _clients = <WebSocketChannel, String>{};
  final _broadcastController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _broadcastController.stream;

  String? get joinUrl {
    if (_server == null || _hostIp == null) return null;
    final roomId = engine.session?.roomId;
    if (roomId == null) return null;
    return 'http://$_hostIp:${AppConstants.serverPort}/join?room=$roomId';
  }

  Future<void> start({required String hostIp}) async {
    _hostIp = hostIp;
    engine.onEvent = _broadcast;

    final router = Router();

    router.get('/join', _servePlayerApp);
    router.get('/', _servePlayerApp);
    router.get('/api/room', _handleGetRoom);
    router.post('/api/players/join', _handleJoin);
    router.post('/api/players/character', _handleSelectCharacter);
    router.post('/api/room/start', _handleStart);
    router.post('/api/game/ready', _handleReady);
    router.post('/api/game/clue/draw', _handleDrawClue);
    router.post('/api/game/clue/transfer', _handleTransferClue);
    router.post('/api/game/clue/reveal', _handleRevealClue);
    router.post('/api/game/accuse', _handleAccuse);
    router.post('/api/game/vote', _handleVote);
    router.post('/api/game/whisper', _handleWhisper);
    router.get('/api/players/me', _handleGetMe);
    router.get('/assets/<file|.*>', _serveAsset);

    final handler = Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    final wsHandler = webSocketHandler((WebSocketChannel channel) {
      channel.stream.listen(
        (message) => _handleWsMessage(channel, message),
        onDone: () => _handleWsDisconnect(channel),
      );
    });

    final cascade = Cascade()
        .add(wsHandler)
        .add(handler);

    _server = await shelf_io.serve(
      cascade.handler,
      InternetAddress.anyIPv4,
      AppConstants.serverPort,
    );
  }

  Future<void> stop() async {
    for (final channel in _clients.keys) {
      await channel.sink.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void _broadcast(String type, Map<String, dynamic> data) {
    final message = jsonEncode({'type': type, ...data});
    for (final channel in _clients.keys.toList()) {
      channel.sink.add(message);
    }
    _broadcastController.add({'type': type, ...data});
  }

  void _sendToToken(String token, String type, Map<String, dynamic> data) {
    final message = jsonEncode({'type': type, ...data});
    for (final entry in _clients.entries) {
      if (entry.value == token) {
        entry.key.sink.add(message);
      }
    }
  }

  void _handleWsDisconnect(WebSocketChannel channel) {
    final token = _clients.remove(channel);
    if (token == null || token == 'tablet') return;

    final player = engine.getPlayerByToken(token);
    if (player != null) {
      engine.setPlayerConnection(player.id, connected: false);
    }
  }

  void _handleWsMessage(WebSocketChannel channel, dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'auth') {
        final token = data['token'] as String?;
        if (token != null && engine.getPlayerByToken(token) != null) {
          final player = engine.getPlayerByToken(token)!;
          _clients[channel] = token;
          if (player.connectionStatus == 'disconnected') {
            engine.setPlayerConnection(player.id, connected: true);
          }
          channel.sink.add(jsonEncode({
            'type': 'auth_ok',
            'session': engine.session?.toJson(),
          }));
        } else if (token == 'tablet') {
          _clients[channel] = 'tablet';
          channel.sink.add(jsonEncode({
            'type': 'auth_ok',
            'role': 'tablet',
            'session': engine.session?.toJson(includeTruth: true),
          }));
        }
      } else if (type == 'ping') {
        channel.sink.add(jsonEncode({'type': 'pong'}));
      }
    } catch (_) {}
  }

  Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  Map<String, String> get _corsHeaders => {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      };

  Response _jsonResponse(Object data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json', ..._corsHeaders},
    );
  }

  String? _getToken(Request request) {
    final auth = request.headers['authorization'];
    if (auth != null && auth.startsWith('Bearer ')) {
      return auth.substring(7);
    }
    return request.headers['x-player-token'];
  }

  Future<Response> _servePlayerApp(Request request) async {
    try {
      final content = await _loadAsset('index.html');
      return Response.ok(
        content,
        headers: {'Content-Type': 'text/html; charset=utf-8', ..._corsHeaders},
      );
    } catch (_) {
      return Response.notFound('Player app not found');
    }
  }

  Future<Response> _serveAsset(Request request, String file) async {
    try {
      final ext = file.split('.').last.toLowerCase();
      final mime = switch (ext) {
        'css' => 'text/css',
        'js' => 'application/javascript',
        'html' => 'text/html',
        _ => 'application/octet-stream',
      };
      final content = await _loadAsset(file);
      return Response.ok(content, headers: {'Content-Type': mime, ..._corsHeaders});
    } catch (_) {
      return Response.notFound('Not found');
    }
  }

  Future<String> _loadAsset(String path) async {
    final segments = path.startsWith('assets/web/')
        ? path.substring('assets/web/'.length)
        : path;
    return AssetServer.instance.load(segments);
  }

  Response _handleGetRoom(Request request) {
    final session = engine.session;
    if (session == null) return _jsonResponse({'error': 'No room'}, statusCode: 404);
    return _jsonResponse(session.toJson());
  }

  Future<Response> _handleJoin(Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final nickname = body['nickname'] as String? ?? 'Player';
    final deviceId = body['deviceId'] as String?;
    final wasExisting = deviceId != null &&
        engine.getPlayerByDeviceId(deviceId) != null;
    final player = engine.joinPlayer(nickname, deviceId: deviceId);
    if (player == null) {
      return _jsonResponse({'error': 'Cannot join'}, statusCode: 400);
    }
    return _jsonResponse({
      'playerId': player.id,
      'token': player.token,
      'roomId': engine.session?.roomId,
      'reconnected': wasExisting,
    });
  }

  Future<Response> _handleSelectCharacter(Request request) async {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final characterId = body['characterId'] as String;
    final ok = engine.selectCharacter(player.id, characterId);
    if (!ok) return _jsonResponse({'error': 'Cannot select'}, statusCode: 400);
    return _jsonResponse({'ok': true, 'player': player.toJson()});
  }

  Response _handleStart(Request request) {
    final ok = engine.startGame();
    if (!ok) return _jsonResponse({'error': 'Cannot start'}, statusCode: 400);
    return _jsonResponse({'ok': true, 'session': engine.session?.toJson(includeTruth: true)});
  }

  Future<Response> _handleReady(Request request) async {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final phase = GamePhase.fromId(body['phase'] as String);
    final ok = engine.markReady(player.id, phase);
    if (!ok) {
      return _jsonResponse({'error': 'Cannot mark ready'}, statusCode: 400);
    }
    return _jsonResponse({'ok': true});
  }

  Response _handleDrawClue(Request request) {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final clue = engine.drawClue(player.id);
    if (clue == null) return _jsonResponse({'error': 'Cannot draw'}, statusCode: 400);
    return _jsonResponse({'clue': clue.toJson()});
  }

  Future<Response> _handleTransferClue(Request request) async {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final ok = engine.transferClue(
      player.id,
      body['toPlayerId'] as String,
      body['clueId'] as String,
    );
    if (!ok) return _jsonResponse({'error': 'Cannot transfer'}, statusCode: 400);
    return _jsonResponse({'ok': true});
  }

  Future<Response> _handleRevealClue(Request request) async {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final clue = engine.revealClue(player.id, body['clueId'] as String);
    if (clue == null) return _jsonResponse({'error': 'Cannot reveal'}, statusCode: 400);
    return _jsonResponse({'clue': clue.toJson()});
  }

  Future<Response> _handleAccuse(Request request) async {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    engine.submitAccusation(player.id, body['content'] as String? ?? '');
    return _jsonResponse({'ok': true});
  }

  Future<Response> _handleVote(Request request) async {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final ok = engine.vote(player.id, body['targetCharacterId'] as String);
    if (!ok) return _jsonResponse({'error': 'Cannot vote'}, statusCode: 400);
    return _jsonResponse({'ok': true});
  }

  Response _handleGetMe(Request request) {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    return _jsonResponse(engine.getPlayerView(player.id));
  }

  Future<Response> _handleWhisper(Request request) async {
    final token = _getToken(request);
    if (token == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final player = engine.getPlayerByToken(token);
    if (player == null) return _jsonResponse({'error': 'Unauthorized'}, statusCode: 401);

    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final toPlayerId = body['toPlayerId'] as String;
    final clueId = body['clueId'] as String?;
    final message = body['message'] as String? ?? '';

    final ok = engine.whisper(
      fromId: player.id,
      toId: toPlayerId,
      clueId: clueId,
      message: message,
    );
    if (!ok) return _jsonResponse({'error': 'Cannot whisper'}, statusCode: 400);

    final toPlayer = engine.getPlayerById(toPlayerId);
    if (toPlayer != null) {
      Map<String, dynamic>? clue;
      if (clueId != null) {
        final session = engine.session!;
        clue = session.scenario.clues
            .firstWhere((c) => c.id == clueId)
            .toJson();
      }
      _sendToToken(toPlayer.token, 'whisper_received', {
        'fromPlayerId': player.id,
        'fromNickname': player.nickname,
        'clueId': clueId,
        'clue': clue,
        'message': message,
      });
    }

    return _jsonResponse({'ok': true});
  }
}
