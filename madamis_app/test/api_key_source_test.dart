import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/config/api_key_source.dart';

void main() {
  test('resolve prefers stored key over env', () {
    expect(ApiKeySource.resolve('stored-key'), 'stored-key');
  });

  test('resolve returns null when nothing set', () {
    final envKey = Platform.environment['GEMINI_API_KEY'];
    if (envKey != null && envKey.isNotEmpty) {
      expect(ApiKeySource.resolve(null), envKey);
      expect(ApiKeySource.resolve(''), envKey);
    } else {
      expect(ApiKeySource.resolve(null), isNull);
      expect(ApiKeySource.resolve(''), isNull);
    }
  });

  test('isFromEnvironment false when stored', () {
    expect(ApiKeySource.isFromEnvironment('stored'), isFalse);
  });
}
