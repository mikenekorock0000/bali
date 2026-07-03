import 'package:flutter_test/flutter_test.dart';
import 'package:madamis_app/config/api_key_source.dart';

void main() {
  test('resolve prefers stored key over env', () {
    expect(ApiKeySource.resolve('stored-key'), 'stored-key');
  });

  test('resolve returns null when nothing set', () {
    expect(ApiKeySource.resolve(null), isNull);
    expect(ApiKeySource.resolve(''), isNull);
  });

  test('isFromEnvironment false when stored', () {
    expect(ApiKeySource.isFromEnvironment('stored'), isFalse);
  });
}
