import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';

import '../models/hotspot_info.dart';

class NetworkService {
  NetworkService._();
  static final NetworkService instance = NetworkService._();

  final _networkInfo = NetworkInfo();
  HotspotInfo? _lastHotspot;

  HotspotInfo? get lastHotspot => _lastHotspot;

  Future<String> getLocalIp() async {
    if (kIsWeb) return '127.0.0.1';

    final wifiIp = await _networkInfo.getWifiIP();
    if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
      return wifiIp;
    }

    // Android hotspot default gateway
    if (Platform.isAndroid) return '192.168.43.1';

    return '127.0.0.1';
  }

  Future<HotspotInfo> startHotspot(String roomId) async {
    if (kIsWeb || !Platform.isAndroid) {
      final ip = await getLocalIp();
      _lastHotspot = HotspotInfo(
        isActive: false,
        localIp: ip,
        message: '同一WiFiに接続してください（IP: $ip）',
      );
      return _lastHotspot!;
    }

    final ssid = 'Madamis-$roomId';
    final password = 'mdms$roomId';

    try {
      // SSID/PW設定は Android SDK 26未満のみ。26+はOSが自動生成
      await WiFiForIoTPlugin.setWiFiAPSSID(ssid);
      await WiFiForIoTPlugin.setWiFiAPPreSharedKey(password);

      final enabled = await WiFiForIoTPlugin.setWiFiAPEnabled(true);
      final actualSsid = await WiFiForIoTPlugin.getWiFiAPSSID();
      final actualPassword = await WiFiForIoTPlugin.getWiFiAPPreSharedKey();

      final ip = enabled ? '192.168.43.1' : await getLocalIp();

      _lastHotspot = HotspotInfo(
        isActive: enabled,
        ssid: actualSsid ?? ssid,
        password: actualPassword ?? password,
        localIp: ip,
        message: enabled
            ? 'ホットスポット起動中'
            : 'ホットスポット自動起動に失敗。設定から手動で有効化してください。',
      );
    } catch (e) {
      final ip = await getLocalIp();
      _lastHotspot = HotspotInfo(
        isActive: false,
        ssid: ssid,
        password: password,
        localIp: ip,
        message: 'ホットスポット起動エラー: $e',
      );
    }

    return _lastHotspot!;
  }

  Future<void> stopHotspot() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await WiFiForIoTPlugin.setWiFiAPEnabled(false);
    } catch (_) {}
    _lastHotspot = null;
  }

  String buildJoinUrl(String hostIp, String roomId) {
    return 'http://$hostIp:8080/join?room=$roomId';
  }
}
