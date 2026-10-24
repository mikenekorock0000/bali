#include "portal.h"

#include <DNSServer.h>
#include <WebServer.h>
#include <WiFi.h>

#include "config.h"
#include "settings.h"
#include "settings_rules.h"

using namespace starter;

SetupPortal portal;

namespace {
WebServer server(80);
DNSServer dns;

// 設定画面。{{名前}} を値に置き換えて返す。パスワード類は表示しない（空欄なら変更しない）
const char PAGE[] PROGMEM = R"HTML(<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>HIJET MONITOR 設定</title>
<style>
:root{--bg:#f4f5f7;--card:#fff;--ink:#1c2430;--sub:#5b6573;--line:#d9dde3;--acc:#1f6feb;--err:#c62828}
@media(prefers-color-scheme:dark){:root{--bg:#11151a;--card:#1a2028;--ink:#e6e9ee;--sub:#9aa4b2;--line:#2c3440;--acc:#4c8dff;--err:#ff6b6b}}
*{box-sizing:border-box}body{margin:0;font:16px/1.5 system-ui,sans-serif;background:var(--bg);color:var(--ink)}
main{max-width:560px;margin:auto;padding:16px}h1{font-size:20px;margin:8px 0}p.s{color:var(--sub);font-size:14px;margin:4px 0 16px}
fieldset{border:1px solid var(--line);border-radius:12px;background:var(--card);margin:0 0 16px;padding:12px 14px}
legend{font-weight:600;padding:0 6px}label{display:block;font-size:14px;color:var(--sub);margin:10px 0 4px}
input,textarea,select{width:100%;padding:10px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--ink);font:inherit}
textarea{height:96px;font-family:ui-monospace,monospace;font-size:14px}
button{font:inherit;padding:10px 14px;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--ink)}
button.p{background:var(--acc);border-color:var(--acc);color:#fff;width:100%;padding:14px;font-weight:600}
.row{display:flex;gap:8px}.row>input{flex:1}.hint{font-size:13px;color:var(--sub)}.err{color:var(--err);font-weight:600}
ul{padding-left:18px;margin:6px 0}li{font-size:14px;cursor:pointer}
</style></head><body><main>
<h1>HIJET MONITOR 設定</h1>
<p class="s">{{reason}}　保存すると再起動します。パスワード類は空欄のままなら変更しません。</p>
<form method="post" action="/save">
<fieldset><legend>Wi-Fi</legend>
<label>主に使う Wi-Fi（車内のテザリングなど）</label>
<div class="row"><input name="ssid1" id="ssid1" value="{{ssid1}}" maxlength="32" required><button type="button" onclick="scan()">探す</button></div>
<ul id="nets"></ul>
<label>パスワード</label><input name="pass1" type="password" maxlength="63" placeholder="{{pass1ph}}">
<label>予備の Wi-Fi（自宅など。なくてもよい）</label><input name="ssid2" value="{{ssid2}}" maxlength="32">
<label>パスワード</label><input name="pass2" type="password" maxlength="63" placeholder="{{pass2ph}}">
</fieldset>
<fieldset><legend>通知（ntfy）</legend>
<label>サーバー</label><input name="server" value="{{server}}" required>
<label>通知のトピック（スマホのアプリで購読）</label><input name="topic" value="{{topic}}" required>
<label>指示のトピック</label><input name="cmdtopic" value="{{cmdtopic}}" required>
<label>状態のトピック（ダッシュボード用。アプリでは購読しない）</label><input name="sttopic" value="{{sttopic}}" required>
<p class="hint">トピック名は英数字・-・_ の 12〜64 文字。名前を知っている人は誰でも読めるので、推測されない長い文字列にしてください。</p>
<label>アクセストークン（ntfy のアカウントを使う場合だけ）</label><input name="token" type="password" placeholder="{{tokenph}}">
</fieldset>
<fieldset><legend>キー（BLE ビーコン）</legend>
<label>1 行に 1 つ（MAC アドレスか uuid:...）。最大 {{maxb}} 個</label><textarea name="beacons">{{beacons}}</textarea>
<button type="button" onclick="ble()">近くの BLE 機器を表示</button><ul id="bles"></ul>
</fieldset>
<fieldset><legend>暗証番号・その他</legend>
<label>暗証番号（数字 4〜8 桁。指示とこの画面の保存に使う）</label><input name="pin" type="password" inputmode="numeric" placeholder="{{pinph}}">
<label>Wi-Fi 書き込み（OTA）のパスワード（8〜32 文字）</label><input name="otapass" type="password" placeholder="{{otaph}}">
<label>電圧の補正係数（テスターの値 ÷ 表示の値、0.8〜1.2）</label><input name="vcal" value="{{vcal}}" inputmode="decimal">
</fieldset>
{{curpin}}
<button class="p" type="submit">保存して再起動</button>
</form>
<p class="hint">この画面は {{ap}} につないでいる間だけ開けます。何もしなければ {{timeout}} 分で終わります。</p>
</main>
<script>
function fill(id,items,f){const u=document.getElementById(id);u.innerHTML='';items.forEach(x=>{const li=document.createElement('li');li.textContent=f(x);li.onclick=()=>x.pick&&x.pick();u.appendChild(li)})}
function scan(){fetch('/scan').then(r=>r.json()).then(a=>fill('nets',a.map(n=>({...n,pick:()=>document.getElementById('ssid1').value=n.ssid})),n=>n.ssid+'（'+n.rssi+'dBm）'))}
function ble(){fetch('/ble').then(r=>r.json()).then(a=>fill('bles',a.map(b=>({...b,pick:()=>{const t=document.querySelector('[name=beacons]');t.value=(t.value.trim()+'\n'+(b.uuid?'uuid:'+b.uuid+':'+b.major+':'+b.minor:b.mac)).trim()}})),b=>b.mac+' '+b.rssi+'dBm '+(b.name||'')+(b.uuid?' iBeacon':'')))}
</script></body></html>)HTML";

String esc(const String& s) {
  String o;
  o.reserve(s.length() + 8);
  for (char c : s) {
    switch (c) {
      case '&': o += "&amp;"; break;
      case '<': o += "&lt;"; break;
      case '>': o += "&gt;"; break;
      case '"': o += "&quot;"; break;
      case '\'': o += "&#39;"; break;
      default: o += c;
    }
  }
  return o;
}

String keepPh(const String& v) { return v.length() ? "（設定済み。変えるときだけ入力）" : "（未設定）"; }

String page(const String& reason, const String& ap) {
  String h = FPSTR(PAGE);
  String b;
  for (const String& x : settings.beacons) {
    if (x.length()) b += x + "\n";
  }
  h.replace("{{reason}}", esc(reason));
  h.replace("{{ssid1}}", esc(settings.ssid1));
  h.replace("{{ssid2}}", esc(settings.ssid2));
  h.replace("{{pass1ph}}", keepPh(settings.pass1));
  h.replace("{{pass2ph}}", keepPh(settings.pass2));
  h.replace("{{server}}", esc(settings.ntfyServer));
  h.replace("{{topic}}", esc(settings.topic));
  h.replace("{{cmdtopic}}", esc(settings.cmdTopic));
  h.replace("{{sttopic}}", esc(settings.stateTopic));
  h.replace("{{tokenph}}", keepPh(settings.token));
  h.replace("{{beacons}}", esc(b));
  h.replace("{{maxb}}", String(MAX_BEACONS));
  h.replace("{{pinph}}", keepPh(settings.pin));
  h.replace("{{otaph}}", keepPh(settings.otaPass));
  h.replace("{{vcal}}", String(settings.vbatCal, 3));
  h.replace("{{ap}}", esc(ap));
  h.replace("{{timeout}}", String(SETUP_TIMEOUT_MS / 60000));
  // 設定済みなら、今の暗証番号を知っている人だけが保存できる（車の近くにいる他人に書き換えさせない）
  h.replace("{{curpin}}", settings.pin.length()
                              ? "<fieldset><legend>確認</legend><label>今の暗証番号</label>"
                                "<input name=\"curpin\" type=\"password\" inputmode=\"numeric\" required></fieldset>"
                              : "");
  return h;
}

void sendMessage(int code, const String& title, const String& body) {
  String h = "<!doctype html><html lang=ja><meta charset=utf-8><meta name=viewport content='width=device-width,"
             "initial-scale=1'><body style='font:16px system-ui;max-width:560px;margin:auto;padding:16px'><h1>" +
             esc(title) + "</h1><p>" + body + "</p><p><a href='/'>設定画面に戻る</a></p></body></html>";
  server.send(code, "text/html; charset=utf-8", h);
}

}  // namespace

String SetupPortal::apName() const {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char b[24];
  snprintf(b, sizeof(b), "HIJET-SETUP-%02X%02X", mac[4], mac[5]);
  return b;
}

void SetupPortal::start(const char* reason, uint32_t nowMs) {
  reason_ = reason;
  startedMs_ = nowMs;
  if (active_) return;
  active_ = true;
  WiFi.mode(WIFI_AP_STA);  // 設定中も、つながる Wi-Fi があれば通知は送り続ける
  WiFi.softAP(apName().c_str(), SETUP_AP_PASS);
  dns.start(53, "*", WiFi.softAPIP());  // どのアドレスを開いても設定画面へ（キャプティブポータル）
  if (!serverUp_) {
    server.on("/", HTTP_GET, [this] { handleRoot(); });
    server.on("/save", HTTP_POST, [this] { handleSave(); });
    server.on("/scan", HTTP_GET, [this] { handleScan(); });
    server.on("/ble", HTTP_GET, [this] { handleBle(); });
    server.onNotFound([this] { handleRedirect(); });
    serverUp_ = true;
  }
  server.begin();
  Serial.printf("setup portal: %s (%s)\n", apName().c_str(), reason);
}

void SetupPortal::stop() {
  if (!active_) return;
  active_ = false;
  server.stop();
  dns.stop();
  WiFi.softAPdisconnect(true);
  WiFi.mode(WIFI_STA);
}

void SetupPortal::loop(uint32_t nowMs) {
  if (!active_) return;
  dns.processNextRequest();
  server.handleClient();
  if (restartAt_ && static_cast<int32_t>(nowMs - restartAt_) >= 0) ESP.restart();
  // 設定済みなら一定時間で終わる（未設定のままなら続ける）
  if (settings.configured() && !restartAt_ && nowMs - startedMs_ > SETUP_TIMEOUT_MS) stop();
}

void SetupPortal::handleRedirect() {
  server.sendHeader("Location", "http://" + WiFi.softAPIP().toString() + "/", true);
  server.send(302, "text/plain", "");
}

void SetupPortal::handleRoot() {
  startedMs_ = millis();  // 画面を開いている間は終わらない
  server.send(200, "text/html; charset=utf-8", page(reason_, apName()));
}

void SetupPortal::handleScan() {
  startedMs_ = millis();
  int n = WiFi.scanNetworks();
  JsonDocument doc;
  JsonArray arr = doc.to<JsonArray>();
  for (int i = 0; i < n && i < 20; ++i) {
    if (WiFi.SSID(i).isEmpty()) continue;
    JsonObject o = arr.add<JsonObject>();
    o["ssid"] = WiFi.SSID(i);
    o["rssi"] = WiFi.RSSI(i);
  }
  WiFi.scanDelete();
  String out;
  serializeJson(doc, out);
  server.send(200, "application/json", out);
}

void SetupPortal::handleBle() {
  startedMs_ = millis();
  JsonDocument doc;
  JsonArray arr = doc.to<JsonArray>();
  if (nearby_) nearby_(arr);
  String out;
  serializeJson(doc, out);
  server.send(200, "application/json", out);
}

void SetupPortal::handleSave() {
  startedMs_ = millis();
  if (settings.pin.length() && server.arg("curpin") != settings.pin) {
    sendMessage(403, "暗証番号が違います", "保存していません。");
    return;
  }
  Settings s = settings;
  auto keepOr = [](const String& in, const String& old) { return in.length() ? in : old; };
  s.ssid1 = server.arg("ssid1");
  s.pass1 = keepOr(server.arg("pass1"), settings.pass1);
  if (s.ssid1 != settings.ssid1 && server.arg("pass1").isEmpty()) s.pass1 = "";  // 別の Wi-Fi に変えたら古いパスワードは使わない
  s.ssid2 = server.arg("ssid2");
  s.pass2 = keepOr(server.arg("pass2"), settings.pass2);
  if (s.ssid2 != settings.ssid2 && server.arg("pass2").isEmpty()) s.pass2 = "";
  if (s.ssid2.isEmpty()) s.pass2 = "";
  s.ntfyServer = server.arg("server");
  s.ntfyServer.trim();
  s.topic = server.arg("topic");
  s.cmdTopic = server.arg("cmdtopic");
  s.stateTopic = server.arg("sttopic");
  s.token = keepOr(server.arg("token"), settings.token);
  s.pin = keepOr(server.arg("pin"), settings.pin);
  s.otaPass = keepOr(server.arg("otapass"), settings.otaPass);
  s.vbatCal = server.arg("vcal").toFloat();
  String lines = server.arg("beacons");
  for (String& b : s.beacons) b = "";
  int n = 0, start = 0;
  while (start <= (int)lines.length() && n < MAX_BEACONS) {
    int nl = lines.indexOf('\n', start);
    if (nl < 0) nl = lines.length();
    String l = lines.substring(start, nl);
    l.trim();
    if (l.length()) s.beacons[n++] = l;
    start = nl + 1;
  }

  String err;
  if (!validSsid(s.ssid1.c_str())) err += "主に使う Wi-Fi の名前（1〜32 文字）<br>";
  if (!validWifiPass(s.pass1.c_str())) err += "Wi-Fi のパスワード（8〜63 文字）<br>";
  if (s.ssid2.length() && (!validSsid(s.ssid2.c_str()) || !validWifiPass(s.pass2.c_str()))) err += "予備の Wi-Fi<br>";
  if (!validServer(s.ntfyServer.c_str())) err += "サーバー（https:// で始まり、末尾に / を付けない）<br>";
  if (!validTopic(s.topic.c_str()) || !validTopic(s.cmdTopic.c_str()) || !validTopic(s.stateTopic.c_str())) {
    err += "トピック名（英数字・-・_ の 12〜64 文字）<br>";
  }
  if (s.topic == s.cmdTopic || s.topic == s.stateTopic || s.cmdTopic == s.stateTopic) err += "3 つのトピックは別の名前に<br>";
  if (!validPin(s.pin.c_str())) err += "暗証番号（数字 4〜8 桁）<br>";
  if (!validOtaPass(s.otaPass.c_str())) err += "OTA のパスワード（8〜32 文字）<br>";
  if (!validCal(s.vbatCal)) err += "電圧の補正係数（0.8〜1.2）<br>";
  if (err.length()) {
    sendMessage(400, "入力を確認してください", "<span style='color:#c62828'>" + err + "</span>保存していません。");
    return;
  }
  s.save();
  settings = s;
  sendMessage(200, "保存しました", "再起動して、新しい設定で Wi-Fi につなぎます。この画面は閉じてかまいません。");
  restartAt_ = millis() + 1500;
}
