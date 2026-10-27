# Kindle ダッシュボードの設定（このファイルは LF 改行で保存すること）

# サーバーの画像 URL（serve.py 起動時に表示される URL）。LAN 内は http を使う
SERVER_URL="http://192.168.1.10:8080/dash.png"

# 更新間隔（秒）。60 なら毎分 0 秒すぎに更新して時計を合わせる
INTERVAL=60

# 何回に 1 回、画面全体を白黒反転させて残像を消すか
FULL_REFRESH_EVERY=15

# 画面を占有する方法
#   pause : Kindle の UI (cvm) を一時停止する（既定・停止すると元に戻る）
#   stop  : UI を停止する（stop lab126_gui）。pause で表示が上書きされる場合に
STOP_MODE=pause

# フロントライトの明るさ（0 = 消灯）。空にすると変更しない
FRONTLIGHT=0

# 起動してから画面を確保するまでの待ち時間（秒）。ライブラリが上書きしてくるなら増やす
START_DELAY=5

# 電源ボタンを押したらダッシュボードを終了する（1 = 有効）
EXIT_ON_POWER_BUTTON=1

# ログ（USB 接続で見える場所。Kindle の dashboard フォルダ内）
LOG_FILE=/mnt/us/dashboard/dashboard.log
