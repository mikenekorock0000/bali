import 'dart:io';

String? readGeminiApiKeyFromEnv() {
  final value = Platform.environment['GEMINI_API_KEY'];
  if (value == null || value.isEmpty) return null;
  return value;
}
