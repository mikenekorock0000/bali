class HotspotInfo {
  HotspotInfo({
    required this.isActive,
    this.ssid,
    this.password,
    this.localIp,
    this.message,
  });

  final bool isActive;
  final String? ssid;
  final String? password;
  final String? localIp;
  final String? message;
}
