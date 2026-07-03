import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/coop_scenario.dart';
import '../models/game_phase.dart';
import '../models/scenario.dart';
import '../models/scenario_config.dart';
import '../services/asset_server.dart';
import '../services/game_engine.dart';
import '../services/scenario_generator.dart';
import '../services/server_service.dart';
import '../services/settings_service.dart';

enum AppScreen { home, scenarioConfig, generating, lobby, game, settings }

class AppState extends ChangeNotifier {
  AppState() {
    AssetServer.instance.preloadAll();
    SettingsService.instance.load();
  }

  final GameEngine _engine = GameEngine();
  final ScenarioGenerator _generator = ScenarioGenerator();
  ServerService? _server;

  AppScreen _screen = AppScreen.home;
  String? _joinUrl;
  String? _roomId;
  String? _lastEvent;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  bool _isRunning = false;

  GenerationProgress _generationProgress = GenerationProgress();
  Scenario? _generatedScenario;
  String? _generationError;

  AppScreen get screen => _screen;
  String? get joinUrl => _joinUrl;
  String? get roomId => _roomId;
  GameEngine get engine => _engine;
  bool get isRunning => _isRunning;
  String? get lastEvent => _lastEvent;
  GenerationProgress get generationProgress => _generationProgress;
  Scenario? get generatedScenario => _generatedScenario;
  String? get generationError => _generationError;
  bool get hasApiKey => SettingsService.instance.hasApiKey;

  GamePhase? get currentPhase => _engine.session?.phase;
  int get playerCount => _engine.session?.players.length ?? 0;
  bool get canStart => _engine.session?.canStart ?? false;
  bool get isStarted => _engine.session?.isStarted ?? false;

  void goToScenarioConfig() {
    _screen = AppScreen.scenarioConfig;
    notifyListeners();
  }

  void goToSettings() {
    _screen = AppScreen.settings;
    notifyListeners();
  }

  void goToHome() {
    _screen = AppScreen.home;
    notifyListeners();
  }

  Future<void> startHostWithCoopScenario({int playerCount = 2}) async {
    final scenario = createCoopScenario(playerCount: playerCount);
    await _startServer(createRoom: () => _engine.createRoomWithScenario(scenario));
  }

  Future<void> startHostWithFixedScenario({int maxPlayers = 4}) async {
    await _startServer(createRoom: () => _engine.createRoom(playerCount: maxPlayers));
  }

  Future<void> generateAndStartHost(ScenarioConfig config) async {
    _generationError = null;
    _generatedScenario = null;
    _generationProgress = GenerationProgress(status: GenerationStatus.running);
    _screen = AppScreen.generating;
    notifyListeners();

    try {
      final scenario = await _generator.generate(
        config,
        onProgress: (p) {
          _generationProgress = p;
          notifyListeners();
        },
      );
      _generatedScenario = scenario;
      await _startServer(createRoom: () => _engine.createRoomWithScenario(scenario));
    } on ScenarioGenerationException catch (e) {
      _generationError = e.message;
      _generationProgress.status = GenerationStatus.failed;
      notifyListeners();
    } catch (e) {
      _generationError = e.toString();
      _generationProgress.status = GenerationStatus.failed;
      notifyListeners();
    }
  }

  Future<void> _startServer({required String Function() createRoom}) async {
    _roomId = createRoom();
    _server = ServerService(engine: _engine);
    await _server!.start();

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

  Future<void> stopHost() async {
    await _eventSub?.cancel();
    await _server?.stop();
    _engine.dispose();
    _isRunning = false;
    _screen = AppScreen.home;
    _joinUrl = null;
    _roomId = null;
    _generatedScenario = null;
    _generationError = null;
    notifyListeners();
  }

  Future<void> saveApiKey(String key) async {
    await SettingsService.instance.saveApiKey(key);
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
