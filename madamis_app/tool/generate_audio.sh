#!/bin/bash
# プレースホルダーBGM/SEをffmpegで生成（本番用は差し替え可）
set -euo pipefail
BGM_DIR="$(dirname "$0")/../assets/audio/bgm"
SE_DIR="$(dirname "$0")/../assets/audio/se"
mkdir -p "$BGM_DIR" "$SE_DIR"

gen_bgm() {
  local name=$1 freq=$2 dur=$3
  ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=${freq}:duration=${dur}" \
    -af "volume=0.25,afade=t=in:st=0:d=2,afade=t=out:st=$((dur-3)):d=3" \
    -codec:a libmp3lame -q:a 6 "$BGM_DIR/$name"
  echo "BGM: $name"
}

gen_se() {
  local name=$1 freq=$2 dur=$3
  ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=${freq}:duration=${dur}" \
    -af "volume=0.5" \
    -codec:a libmp3lame -q:a 5 "$SE_DIR/$name"
  echo "SE: $name"
}

# BGM（45秒・フェーズ別トーン）
gen_bgm bgm_lobby.mp3 196 45
gen_bgm bgm_tension.mp3 220 45
gen_bgm bgm_mystery.mp3 185 45
gen_bgm bgm_investigation.mp3 247 45
gen_bgm bgm_discussion.mp3 262 45
gen_bgm bgm_suspense.mp3 165 45
gen_bgm bgm_ending.mp3 330 45

# SE（短い効果音）
gen_se se_join.mp3 523 0.25
gen_se se_clue.mp3 440 0.2
gen_se se_vote.mp3 349 0.3
gen_se se_truth.mp3 277 0.6
gen_se se_phase.mp3 392 0.35
gen_se se_correct.mp3 659 0.4
gen_se se_wrong.mp3 185 0.5

echo "Done: $(ls "$BGM_DIR"/*.mp3 | wc -l) BGM, $(ls "$SE_DIR"/*.mp3 | wc -l) SE"
