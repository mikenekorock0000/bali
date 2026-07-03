import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _apiKeyKey = 'gemini_api_key';
  static const _soundEnabledKey = 'sound_enabled';
  static const _volumeKey = 'volume';

  String? _apiKey;
  bool _soundEnabled = true;
  double _volume = 0.8;

  String? get apiKey => _apiKey;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;
  bool get soundEnabled => _soundEnabled;
  double get volume => _volume;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_apiKeyKey);
    _soundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
    _volume = prefs.getDouble(_volumeKey) ?? 0.8;
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key.trim());
    _apiKey = key.trim();
  }

  Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
    _apiKey = null;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
    _soundEnabled = enabled;
  }

  Future<void> setVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, volume.clamp(0.0, 1.0));
    _volume = volume.clamp(0.0, 1.0);
  }
}
