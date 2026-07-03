/// AIシナリオ生成パイプラインの品質・コスト設定。
class AiPipelineConfig {
  /// 創作ステップ用（世界観・台本・手がかり）
  static const primaryModel = 'gemini-2.5-flash';

  /// 監査・修復・仕上げ用（低温度で厳密に）
  static const auditModel = 'gemini-2.5-flash';

  /// フル生成の最大試行回数
  static const maxAttempts = 8;

  /// 1試行あたりのAI修復パス（整合性エラー時）
  static const maxRepairPasses = 2;

  static const creativeTemperature = 0.85;
  static const auditTemperature = 0.15;
  static const repairTemperature = 0.3;
}
