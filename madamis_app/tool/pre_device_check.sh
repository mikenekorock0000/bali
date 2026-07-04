#!/usr/bin/env bash
# 実機テスト前にプレイヤー参加・あらすじ確認フローを自動検証する。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Running pre-device checks (API flow + web asset wiring)..."
flutter test \
  test/server_api_flow_test.dart \
  test/web_player_assets_test.dart \
  test/player_automated_test.dart \
  test/game_engine_test.dart

echo ""
echo "All pre-device checks passed."
echo "Optional: PCブラウザで http://<タブレットIP>:8080/join を開き、"
echo "  参加 → ゲーム開始 → 確認しました の手動確認もできます。"
