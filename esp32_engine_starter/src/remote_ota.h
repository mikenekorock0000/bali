#pragma once
// 遠隔更新：ダッシュボードが ntfy の指示用トピックに添付したファームウェアを取りに行って書き込む。
// 同じ Wi-Fi にいなくても更新できる。書き込む前に SHA-256 を署名付きの指示の値と照らし合わせる
// （添付の URL は署名に含まれないので、中身はこの値で確かめる）。
#include <Arduino.h>

#include "notifier.h"

// 成功したら true（呼んだ側で再起動する）。失敗したら err に理由
bool remoteOtaUpdate(Notifier& notifier, const String& url, const String& sha256Hex, String& err);
