import 'env_reader_stub.dart'
    if (dart.library.io) 'env_reader_io.dart' as env_reader;

/// GEMINI_API_KEY の解決（保存値 > 環境変数 > --dart-define）
class ApiKeySource {
  static const envVarName = 'GEMINI_API_KEY';

  static String? resolve(String? stored) {
    if (stored != null && stored.isNotEmpty) return stored;

    const fromDefine = String.fromEnvironment(envVarName);
    if (fromDefine.isNotEmpty) return fromDefine;

    return env_reader.readGeminiApiKeyFromEnv();
  }

  static bool isFromEnvironment(String? stored) {
    if (stored != null && stored.isNotEmpty) return false;
    const fromDefine = String.fromEnvironment(envVarName);
    if (fromDefine.isNotEmpty) return true;
    final fromEnv = env_reader.readGeminiApiKeyFromEnv();
    return fromEnv != null && fromEnv.isNotEmpty;
  }
}
