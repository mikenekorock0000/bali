import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hotspot_info.dart';
import '../services/app_state.dart';

class HotspotInfoCard extends StatelessWidget {
  const HotspotInfoCard({super.key, required this.info});

  final HotspotInfo info;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  info.isActive ? Icons.wifi_tethering : Icons.wifi,
                  size: 18,
                  color: info.isActive ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  info.isActive ? 'ホットスポット起動中' : 'ネットワーク接続',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            if (info.ssid != null) ...[
              const SizedBox(height: 8),
              Text('SSID: ${info.ssid}', style: const TextStyle(fontSize: 13)),
              Text('PW: ${info.password}', style: const TextStyle(fontSize: 13)),
            ],
            if (info.localIp != null) ...[
              const SizedBox(height: 4),
              Text('IP: ${info.localIp}', style: const TextStyle(fontSize: 13)),
            ],
            if (info.message != null) ...[
              const SizedBox(height: 4),
              Text(
                info.message!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HotspotInfoBanner extends StatelessWidget {
  const HotspotInfoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final info = context.watch<AppState>().hotspotInfo;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: HotspotInfoCard(info: info),
    );
  }
}
