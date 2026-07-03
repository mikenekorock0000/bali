import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/coop_scenario.dart';
import '../models/game_phase.dart';
import '../models/hotspot_info.dart';
import '../models/saved_scenario_summary.dart';
import '../models/scenario.dart';
import '../models/scenario_config.dart';
import '../services/asset_server.dart';
import '../services/audio_service.dart';
import '../services/game_engine.dart';
import '../services/network_service.dart';
import '../services/save_service.dart';
import '../services/scenario_asset_loader.dart';
import '../services/scenario_generator.dart';
import '../services/server_service.dart';
import '../services/settings_service.dart';

enum AppScreen { home, scenarioConfig, generating, lobby, game, settings }

class AppState extends ChangeNotifier {
  AppState() {
    AssetServer.instance.preloadAll();
    SettingsService.instance.load();
  }

  GameEngine _engine = GameEngine();
  final ScenarioGenerator _generator = ScenarioGenerator();
  ServerService? _server;

  AppScreen _screen = AppScreen.home;
  String? _joinUrl;
  String? _roomId;
  String? _lastEvent;
  GamePhase? _phaseOverlay;
  Timer? _phaseOverlayTimer;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _autoSaveTimer;
  bool _isRunning = false;

  GenerationProgress _generationProgress = GenerationProgress();
  Scenario? _generatedScenario;
  String? _generationError;
  HotspotInfo? _hotspotInfo;
  List<SaveSummary> _saves = [];
  List<SavedScenarioSummary> _savedScenarios = [];
  bool _loadingSavedScenarios = false;
  String? _savedScenarioError;

  AppScreen get screen => _screen;
  String? get joinUrl => _joinUrl;
  String? get roomId => _roomId;
  GameEngine get engine => _engine;
  bool get isRunning => _isRunning;
  String? get lastEvent => _lastEvent;
  GamePhase? get phaseOverlay => _phaseOverlay;
  GenerationProgress get generationProgress => _generationProgress;
  Scenario? get generatedScenario => _generatedScenario;
  String? get generationError => _generationError;
  HotspotInfo? get hotspotInfo => _hotspotInfo;
  List<SaveSummary> get saves => _saves;
  List<SavedScenarioSummary> get savedScenarios => _savedScenarios;
  bool get loadingSavedScenarios => _loadingSavedScenarios;
  String? get savedScenarioError => _savedScenarioError;
  bool get hasApiKey => SettingsService.instance.hasApiKey;
  bool get soundEnabled => SettingsService.instance.soundEnabled;

  GamePhase? get currentPhase => _engine.session?.phase;
  int get playerCount => _engine.session?.players.length ?? 0;
  bool get canStart => _engine.session?.canStart ?? false;
  bool get isStarted => _engine.session?.isStarted ?? false;

  Future<void> refreshSavedScenarios() async {
    _loadingSavedScenarios = true;
    _savedScenarioError = null;
    notifyListeners();
    try {
      _savedScenarios = await ScenarioAssetLoader.instance.listSummaries();
    } catch (e) {
      _savedScenarios = [];
      _savedScenarioError = e.toString();
    }
    _loadingSavedScenarios = false;
    notifyListeners();
  }

  Future<void> refreshSaves() async {
    try {
      _saves = await SaveService.instance.listSaves();
    } catch (_) {
      _saves = [];
    }
    notifyListeners();
  }

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
    refreshSaves();
    refreshSavedScenarios();
    notifyListeners();
  }

  Future<void> startHostWithSavedScenario(String assetPath) async {
    _savedScenarioError = null;
    notifyListeners();
    try {
      final scenario = await ScenarioAssetLoader.instance.loadScenario(assetPath);
      await _startServer(createRoom: () => _engine.createRoomWithScenario(scenario));
    } catch (e) {
      _savedScenarioError = 'シナリオの読み込みに失敗しました: $e';
      notifyListeners();
    }
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
        apiKey: SettingsService.instance.apiKey,
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

  Future<void> resumeFromSave(String saveId) async {
    final session = await SaveService.instance.loadSession(saveId);
    if (session == null) return;

    _engine = GameEngine();
    _engine.restoreSession(session);
    await _startServer(
      createRoom: () => session.roomId,
      skipCreateRoom: true,
    );

    _screen = session.isStarted ? AppScreen.game : AppScreen.lobby;
    notifyListeners();
  }

  Future<void> _startServer({
    required String Function() createRoom,
    bool skipCreateRoom = false,
  }) async {
    if (!skipCreateRoom) {
      _roomId = createRoom();
    } else {
      _roomId = _engine.session?.roomId;
    }

    _hotspotInfo = await NetworkService.instance.startHotspot(_roomId!);
    final hostIp = _hotspotInfo!.localIp ?? await NetworkService.instance.getLocalIp();

    _server = ServerService(engine: _engine);
    await _server!.start(hostIp: hostIp);

    _joinUrl = _server!.joinUrl;
    _isRunning = true;
    if (_screen != AppScreen.game) {
      _screen = AppScreen.lobby;
    }

    _eventSub?.cancel();
    _eventSub = _server!.events.listen(_handleServerEvent);

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) => autoSave());

    notifyListeners();
  }

  void _handleServerEvent(Map<String, dynamic> event) {
    _lastEvent = event['type'] as String?;
    AudioService.instance.onEvent(_lastEvent ?? '');

    if (_lastEvent == 'phase_changed') {
      final phaseId = event['phase'] as String?;
      if (phaseId != null) {
        final phase = GamePhase.fromId(phaseId);
        AudioService.instance.onPhaseChanged(phase);
        _phaseOverlay = phase;
        _phaseOverlayTimer?.cancel();
        _phaseOverlayTimer = Timer(const Duration(seconds: 3), () {
          _phaseOverlay = null;
          notifyListeners();
        });
      }
    }

    autoSave();
    notifyListeners();
  }

  Future<void> autoSave() async {
    final session = _engine.session;
    if (session == null || !session.isStarted) return;
    try {
      await SaveService.instance.saveSession(session);
    } catch (_) {}
  }

  void startGame() {
    if (_engine.startGame()) {
      _screen = AppScreen.game;
      autoSave();
      notifyListeners();
    }
  }

  Future<void> stopHost() async {
    await autoSave();
    await _eventSub?.cancel();
    await _server?.stop();
    await NetworkService.instance.stopHotspot();
    await AudioService.instance.stopAll();
    _autoSaveTimer?.cancel();
    _engine.dispose();
    _engine = GameEngine();
    _isRunning = false;
    _screen = AppScreen.home;
    _joinUrl = null;
    _roomId = null;
    _hotspotInfo = null;
    _generatedScenario = null;
    _generationError = null;
    await refreshSaves();
    notifyListeners();
  }

  Future<void> saveApiKey(String key) async {
    await SettingsService.instance.saveApiKey(key);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool enabled) async {
    await SettingsService.instance.setSoundEnabled(enabled);
    if (!enabled) await AudioService.instance.stopAll();
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    await SettingsService.instance.setVolume(volume);
    notifyListeners();
  }

  Future<void> deleteSave(String id) async {
    await SaveService.instance.deleteSave(id);
    await refreshSaves();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _autoSaveTimer?.cancel();
    _phaseOverlayTimer?.cancel();
    _server?.stop();
    NetworkService.instance.stopHotspot();
    AudioService.instance.stopAll();
    _engine.dispose();
    super.dispose();
  }
}
