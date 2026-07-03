import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_phase.dart';
import '../services/asset_server.dart';
import '../services/game_engine.dart';
import '../services/server_service.dart';

enum AppScreen { home, lobby, game }

class AppState extends ChangeNotifier {
  AppState() {
    AssetServer.instance.preloadAll();
  }

  final GameEngine _engine = GameEngine();
  ServerService? _server;

  AppScreen _screen = AppScreen.home;
  String? _joinUrl;
  String? _serverIp;
  String? _roomId;
  String? _lastEvent;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  bool _isRunning = false;

  AppScreen get screen => _screen;
  String? get joinUrl => _joinUrl;
  String? get serverIp => _serverIp;
  String? get roomId => _roomId;
  GameEngine get engine => _engine;
  bool get isRunning => _isRunning;
  String? get lastEvent => _lastEvent;

  GamePhase? get currentPhase => _engine.session?.phase;
  int get playerCount => _engine.session?.players.length ?? 0;
  bool get canStart => _engine.session?.canStart ?? false;
  bool get isStarted => _engine.session?.isStarted ?? false;

  Future<void> startHost({int maxPlayers = 4}) async {
    _roomId = _engine.createRoom(playerCount: maxPlayers);
    _server = ServerService(engine: _engine);
    await _server!.start();

    _serverIp = _server!.joinUrl?.split('://').last.split('/').first.split(':').first;
    _joinUrl = _server!.joinUrl;
    _isRunning = true;
    _screen = AppScreen.lobby;

    _eventSub = _server!.events.listen((event) {
      _lastEvent = event['type'] as String?;
      notifyListeners();
    });

    notifyListeners();
  }

  void startGame() {
    if (_engine.startGame()) {
      _screen = AppScreen.game;
      notifyListeners();
    }
  }

  void goToLobby() {
    _screen = AppScreen.lobby;
    notifyListeners();
  }

  Future<void> stopHost() async {
    await _eventSub?.cancel();
    await _server?.stop();
    _engine.dispose();
    _isRunning = false;
    _screen = AppScreen.home;
    _joinUrl = null;
    _roomId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _server?.stop();
    _engine.dispose();
    super.dispose();
  }
}
